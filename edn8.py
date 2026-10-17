#!/usr/bin/env python3
"""EverDrive-N8 PRO over USB: upload a ROM to usb-games/ and boot it from the menu, plus SD and cart memory access.
"""
import sys, os, time, struct, argparse, atexit

import serial
from serial.tools import list_ports

PROTOCOL_ID_N8   = 0x06
DEVICE_ID_N8_PRO = 0x17
STATUS_KEY       = 0x5A   # new-firmware status key
STATUS_KEY_OLD   = 0xA5   # legacy status key (N8/Mega still answer with it)
USB_VID          = 0x38DF  # KRIKZZ-IT

# NESCD: the cart on the PGA2350's USB host, its console on a debugprobe
DEBUGPROBE_VID     = 0x2E8A
DEBUGPROBE_PID     = 0x000C
NESCD_CONSOLE_BAUD = 115200
NESCD_BRIDGE_BAUD  = int(os.environ.get("EDN8_BRIDGE_BAUD", 3000000))
NESCD_PROMPT       = b"cd> "
NESCD_BRIDGE_UP    = b"break to exit\r\n"

CMD_STATUS   = 0x10
CMD_STATUS2  = 0x40
CMD_MEM_WR   = 0x1A
CMD_MEM_RD   = 0x19
CMD_FPG_USB  = 0x1E
CMD_SYS_INF  = 0x26
CMD_F_DIR_LD   = 0xC5
CMD_F_DIR_SIZE = 0xC6
CMD_F_DIR_GET  = 0xC8
DIR_GET_MAX    = 32     # entries one CMD_F_DIR_GET gives; 33 answers 0x82 (measured 2026-10-16)
CMD_F_FOPN   = 0xC9
CMD_F_FRD    = 0xCA
CMD_F_FWR    = 0xCC
CMD_F_FCLOSE = 0xCE
CMD_F_FINFO  = 0xD0
CMD_F_DIR_MK = 0xD2
CMD_F_DEL    = 0xD3

# PI bus (everdrive.h:102-107)
ADDR_PRG = 0x0000000        # 8 MB PRG
ADDR_CHR = 0x0800000        # 8 MB CHR
ADDR_SRM = 0x1000000        # 256 KB battery RAM
ADDR_FCI_CFG  = 0x1800000   # mapper config; everything below it is cart memory
ADDR_FCI_FIFO = 0x1810000   # host->cart fifo, which carries the menu commands
ADDR_SCFG     = 0x1800020   # sys_cfg's 16 bytes (pi.sv: ce_cfg = addr[15:4] == 2)

FA_READ          = 0x01
FA_WRITE         = 0x02
FA_CREATE_ALWAYS = 0x08
FS_MAKEPATH      = 0x80

ACK_BLOCK = 1024   # file and FPGA writes wait for an ack before each block


class EDN8:
    def __init__(self, port=None):
        self.port = None
        self.bridged = False
        self._open(port)
        atexit.register(self.close)

    @staticmethod
    def _candidates(port):
        # (device, via NESCD): a cart on this PC's USB first, else every debugprobe console
        ports = list_ports.comports()
        probes = [p.device for p in ports if (p.vid, p.pid) == (DEBUGPROBE_VID, DEBUGPROBE_PID)]
        if port:
            return [(port, os.path.realpath(port) in probes)]
        return ([(p.device, False) for p in ports if p.vid == USB_VID] +
                [(d, True) for d in sorted(probes)])

    def _open(self, port):
        last = "no KRIKZZ device and no debugprobe console"
        for dev, via in self._candidates(port):
            for attempt in (0, 1):          # one cold-start retry, like edlink
                try:
                    s = (self._bridge_open(dev) if via else
                         serial.Serial(dev, baudrate=921600, timeout=0.2, write_timeout=10))
                except Exception as e:
                    last = e
                    break
                try:
                    self.port, self.bridged = s, via
                    s.timeout = 0.2
                    # wake: 66 zero bytes clear any half-parsed command, drain reply
                    s.write(bytes(66)); s.flush()
                    time.sleep(0.05)
                    s.reset_input_buffer()
                    self._identify()
                    s.timeout = 2.0
                    self.dev_path = f"{dev} via NESCD @ {s.baudrate} baud" if via else dev
                    return
                except Exception as e:
                    last = e
                    self.close()
                    time.sleep(0.1)
        raise SystemExit(f"EverDrive-N8 not found ({last})")

    # the NESCD console turns into a raw pipe with `X <baud>` and back with a break
    @staticmethod
    def _break(s):
        s.break_condition = True
        time.sleep(0.02)
        s.break_condition = False

    @staticmethod
    def _expect(s, mark, timeout):
        end, buf = time.time() + timeout, b""
        while time.time() < end:
            buf += s.read(256)
            if mark in buf or (mark != NESCD_PROMPT and NESCD_PROMPT in buf):
                return buf
        raise IOError(f"NESCD console: no {mark!r} (got {buf[-120:]!r})")

    def _bridge_open(self, dev):
        s = serial.Serial(dev, NESCD_CONSOLE_BAUD, timeout=0.05, write_timeout=10)
        try:
            self._break(s)                   # ends a bridge a killed run left up; the prompt takes it as a NUL
            for _ in range(3):
                time.sleep(0.05)
                for _ in range(12):              # rub out a half-typed line; each echoes 3 bytes, so pace them
                    s.write(b"\x08" * 8)
                    time.sleep(0.003)
                s.write(b"\r")
                try:
                    self._expect(s, NESCD_PROMPT, 1.0)
                    break
                except IOError as e:
                    err = e
            else:
                raise err
            time.sleep(0.05)
            s.reset_input_buffer()
            s.write(f"X {NESCD_BRIDGE_BAUD}\r".encode())
            out = self._expect(s, NESCD_BRIDGE_UP, 3.0)
            if NESCD_BRIDGE_UP not in out:
                raise IOError("NESCD refused the bridge: " + out.decode("latin-1").strip())
            s.baudrate = NESCD_BRIDGE_BAUD
            time.sleep(0.01)
            s.reset_input_buffer()
            return s
        except Exception:
            s.close()
            raise

    def _bridge_close(self, s):
        s.flush()
        time.sleep(0.02)                     # the probe's queue reaches the wire ahead of the break
        self._break(s)
        s.baudrate = NESCD_CONSOLE_BAUD
        s.timeout = 0.05
        try:
            out = self._expect(s, NESCD_PROMPT, 2.0).decode("latin-1")
        except IOError as e:
            sys.stderr.write(f"warning: {e}\n")
            return
        line = next((l for l in out.splitlines() if "bridge: closed" in l), "")
        if "closed - " in line:
            sys.stderr.write(f"warning: NESCD {line.strip()}\n")

    def _tx(self, data):
        self.port.write(data)

    def _rx(self, n):
        buf = bytearray()
        while len(buf) < n:
            chunk = self.port.read(n - len(buf))
            if not chunk:
                raise IOError(f"read timeout ({len(buf)}/{n} bytes)")
            buf.extend(chunk)
        return bytes(buf)

    def _tx_data(self, data):
        # mirror edlink Link.TxData: 4096-byte blocks, with the 512->256 quirk
        mv = memoryview(data)
        off, n = 0, len(mv)
        while n > 0:
            block = min(n, 4096)
            if block == 512:
                block = 256
            self.port.write(mv[off:off + block])
            off += block; n -= block

    def _tx_data_ack(self, data):
        mv = memoryview(data)
        off, n = 0, len(mv)
        while n > 0:
            ack = self._rx(1)[0]
            if ack != 0:
                raise IOError(f"tx ack error 0x{ack:02X}")
            block = min(n, ACK_BLOCK)
            self._tx_data(mv[off:off + block])
            off += block; n -= block

    # little-endian: edlink runs the N8 with SwapEndians=false
    def _tx_cmd(self, cmd):
        self._tx(bytes([ord('+'), ord('+') ^ 0xff, cmd, cmd ^ 0xff]))
    def _tx8(self, v):  self._tx(bytes([v & 0xff]))
    def _tx16(self, v): self._tx(struct.pack('<H', v & 0xFFFF))
    def _tx32(self, v): self._tx(struct.pack('<I', v & 0xFFFFFFFF))
    def _rx8(self):  return self._rx(1)[0]
    def _rx16(self): return struct.unpack('<H', self._rx(2))[0]
    def _rx32(self): return struct.unpack('<I', self._rx(4))[0]

    def _tx_string(self, s):
        b = s.encode('ascii')
        self._tx16(len(b)); self._tx_data(b)

    def _identify(self):
        # edlink GetDeviceConfig(): probe with STATUS2 then STATUS
        self._tx_cmd(CMD_STATUS2)
        self._tx_cmd(CMD_STATUS)
        a = self._rx(2)                          # [key, protocol]
        if a[0] != STATUS_KEY:
            raise IOError(f"unexpected status key 0x{a[0]:02X}")
        b = self._rx(2)                          # [device, xx]
        protocol, device = a[1], b[0]
        if protocol in (0x05, PROTOCOL_ID_N8):   # Mega / N8 -> "Gen2"
            self._rx(2)                          # drain trailing STATUS reply
        # edlink GetID(): one more STATUS; N8 answers [status, 0xA5]
        self._tx_cmd(CMD_STATUS)
        st = self._rx(2)
        if st[1] != STATUS_KEY_OLD:
            raise IOError(f"invalid status key (got {st.hex()})")
        if protocol != PROTOCOL_ID_N8 or device != DEVICE_ID_N8_PRO:
            raise IOError(f"not an N8 PRO (proto=0x{protocol:02X} dev=0x{device:02X})")
        self.protocol, self.device = protocol, device

    def _status(self):
        self._tx_cmd(CMD_STATUS)
        st = self._rx(2)                         # [status, 0xA5]
        if st[1] != STATUS_KEY_OLD:
            raise IOError(f"unexpected status resp {st.hex()}")
        return st[0]

    def _check(self):
        r = self._status()
        if r != 0:
            raise IOError(f"operation error 0x{r:02X}")

    @staticmethod
    def _guard(addr, length, force):
        # PRG and SRM share the bus the 6502 runs and reads from: host DMA there crashes the running program
        for lo, hi, name in ((ADDR_PRG, ADDR_CHR, 'PRG'), (ADDR_SRM, ADDR_FCI_CFG, 'SRM')):
            if addr < hi and addr + length > lo and not force:
                raise IOError(f"0x{addr:07X}+{length} is {name} PSRAM, which the NES runs from; "
                              "only with force=True (--force) while the 6502 is parked off it")

    def mem_wr(self, addr, data, force=False):
        self._guard(addr, len(data), force)
        # exec 0: everdrive.c's 0xAA is the 6502's halt-and-DMA and wedges the MCU when the host sends it
        self._tx_cmd(CMD_MEM_WR)
        self._tx32(addr); self._tx32(len(data)); self._tx8(0)
        self._tx_data(data)

    def mem_rd(self, addr, length, force=False):
        self._guard(addr, length, force)
        self._tx_cmd(CMD_MEM_RD)
        self._tx32(addr); self._tx32(length); self._tx8(0)
        return self._rx(length)

    def mapper(self):
        # the mapper sys_cfg holds (scfg 0, scfg 2 bits 7-4); read through the MCU, nothing reaches the 6502 FIFO
        b = self.mem_rd(ADDR_SCFG, 3)
        return b[0] | (b[2] >> 4) << 8

    def _fifo_wr(self, data):
        self.mem_wr(ADDR_FCI_FIFO, data)

    def _fifo_tx_string(self, s):
        b = s.encode('ascii')
        self._fifo_wr(struct.pack('<H', len(b)))
        self._fifo_wr(b)

    def fpg_init(self, data):
        self._tx_cmd(CMD_FPG_USB)
        self._tx32(len(data))
        self._tx_data_ack(data)
        self._check()

    def _dir_make(self, path):
        self._tx_cmd(CMD_F_DIR_MK); self._tx_string(path)
        r = self._status()
        if r not in (0, 8):                      # 8 == already exists
            raise IOError(f"mkdir '{path}' error 0x{r:02X}")

    def _make_path(self, path):
        i = 0
        while True:
            i = path.find('/', i + 1)
            if i < 0:
                return
            self._dir_make(path[:i])

    def dir_list(self, path):
        """[(name, is a folder, size)] in path, sorted as the MCU sorts them: folders first"""
        self._tx_cmd(CMD_F_DIR_LD); self._tx8(1); self._tx_string(path)
        self._check()
        self._tx_cmd(CMD_F_DIR_SIZE)
        n = self._rx16()
        out = []
        for first in range(0, n, DIR_GET_MAX):
            count = min(DIR_GET_MAX, n - first)
            self._tx_cmd(CMD_F_DIR_GET); self._tx16(first); self._tx16(count); self._tx16(255)
            for _ in range(count):
                r = self._rx8()
                if r:
                    raise IOError(f"list '{path}' error 0x{r:02X}")
                size = self._rx32()
                self._rx(4)
                attr = self._rx8()
                out.append((self._rx(self._rx16()).decode('latin-1'), bool(attr & 0x10), size))
        return out

    def file_delete(self, path):
        """Delete an SD file or empty folder; True when it was there."""
        self._tx_cmd(CMD_F_DEL); self._tx_string(path)
        r = self._status()
        if r in (4, 5):                          # FR_NO_FILE, FR_NO_PATH
            return False
        if r:
            raise IOError(f"delete '{path}' error 0x{r:02X}")
        return True

    def file_open(self, path, mode):
        if (mode & (FA_WRITE | FS_MAKEPATH)) == (FA_WRITE | FS_MAKEPATH):
            self._make_path(path)
        self._tx_cmd(CMD_F_FOPN)
        self._tx8(mode & ~FS_MAKEPATH)
        self._tx_string(path)
        self._check()

    def file_write(self, data):
        self._tx_cmd(CMD_F_FWR); self._tx32(len(data))
        self._tx_data_ack(data)
        self._check()

    def file_close(self):
        self._tx_cmd(CMD_F_FCLOSE); self._check()

    def file_size(self, path):
        # FileInfo as edio's ed_rx_file_info: u32 size, date, time, attrib, name
        self._tx_cmd(CMD_F_FINFO); self._tx_string(path)
        r = self._rx8()
        if r:
            raise IOError(f"info '{path}' error 0x{r:02X}")
        size = self._rx32()
        self._rx(5)
        self._rx(self._rx16())
        return size

    def file_read(self, n):
        # one status byte ahead of each 4 KiB block, like edlink's fileRead
        self._tx_cmd(CMD_F_FRD); self._tx32(n)
        out = bytearray()
        while len(out) < n:
            r = self._rx8()
            if r:
                raise IOError(f"file read error 0x{r:02X}")
            out += self._rx(min(4096, n - len(out)))
        return bytes(out)

    def get_file(self, sd_path, local_path, chunk=1 << 18, progress=True):
        """Download an SD file to a local path."""
        n = self.file_size(sd_path)
        self.file_open(sd_path, FA_READ)
        t0, data = time.time(), bytearray()
        while len(data) < n:
            data += self.file_read(min(chunk, n - len(data)))
            if progress:
                dt = time.time() - t0
                sys.stderr.write(f"\r  {sd_path}: {len(data)/1024:.0f}/{n/1024:.0f} KiB "
                                 f"({len(data)/1024/max(dt,1e-3):.0f} KiB/s)")
                sys.stderr.flush()
        self.file_close()
        if progress:
            sys.stderr.write("\n")
        open(local_path, 'wb').write(data)

    def put_file(self, local_path, sd_path, chunk=1 << 18, progress=True):
        """Upload a local file to an SD path, making its folders; chunked for the progress line."""
        data = open(local_path, 'rb').read()
        n = len(data)
        self.file_open(sd_path, FA_WRITE | FA_CREATE_ALWAYS | FS_MAKEPATH)
        t0, off = time.time(), 0
        while off < n:
            self.file_write(data[off:off + chunk]); off += min(chunk, n - off)
            if progress:
                dt = time.time() - t0
                sys.stderr.write(f"\r  {sd_path}: {off/1024:.0f}/{n/1024:.0f} KiB "
                                 f"({off/1024/max(dt,1e-3):.0f} KiB/s)")
                sys.stderr.flush()
        self.file_close()
        if progress:
            sys.stderr.write("\n")

    # menu commands, answered only on the ROM select screen
    def _mcmd(self, ch):
        self._fifo_wr(bytes([ord('*'), ord(ch)]))

    def menu_test(self):
        self._mcmd('t')
        try:
            r = self._rx8()
        except IOError:
            raise IOError("menu not responding -- is the cart on the ROM select screen?")
        if r != ord('k'):
            raise IOError(f"menu test: unexpected response 0x{r:02X}")

    def menu_reset(self):
        self._mcmd('r'); self._rx8()
    def menu_install(self, path):
        self._mcmd('n')
        self._fifo_tx_string(path)
        old = self.port.timeout
        self.port.timeout = 30.0                 # the menu reads the ROM off the SD and sets up its mapper
        try:
            r = self._rx8()
            if r != 0:
                raise IOError(f"app install error 0x{r:02X}")
            return self._rx16()                  # mapper index
        finally:
            self.port.timeout = old

    def menu_start(self):
        self._mcmd('s')

    def fifo_send(self, data):
        """Raw bytes into the host->cart fifo, for a running ROM to read (edlink `fifowr`)."""
        self._fifo_wr(data)

    def run(self, rom_path, fpga_path=None, rbf_path=None):
        rom = open(rom_path, 'rb').read()
        name = os.path.basename(rom_path)
        dev_path = "usb-games/" + name

        self.menu_test()

        if rbf_path:
            # firmware 2.15+ loads a same-named .rbf sitting next to the ROM; CMD_FPG_USB would wipe the menu config
            rbf_dev = "usb-games/" + os.path.splitext(name)[0] + ".rbf"
            print(f"  core      : {os.path.basename(rbf_path)} -> sd:{rbf_dev}")
            self.put_file(rbf_path, rbf_dev, progress=False)

        if fpga_path:
            core = open(fpga_path, 'rb').read()
            print(f"  fpga core : {os.path.basename(fpga_path)} ({len(core)} B)")
            self.fpg_init(core)

        print(f"  uploading : {name} ({len(rom)} B) -> sd:{dev_path}")
        t0 = time.time()
        self.file_open(dev_path, FA_WRITE | FA_CREATE_ALWAYS | FS_MAKEPATH)
        self.file_write(rom)
        self.file_close()
        dt = time.time() - t0
        print(f"  sent      : {len(rom)/1024:.0f} KiB in {dt:.1f}s "
              f"({len(rom)/1024/max(dt,1e-3):.0f} KiB/s)")

        map_idx = self.menu_install(dev_path)
        print(f"  installed : mapper index {map_idx}")
        self.menu_start()
        print("  booting.  game is running on the NES.")

    def info(self):
        self._tx_cmd(CMD_SYS_INF)
        b = self._rx(64)
        serial_g, serial_l = struct.unpack_from('<II', b, 20)
        boot_ctr, game_ctr = struct.unpack_from('<II', b, 28)
        sw_ver, hw_ver, boot_ver = struct.unpack_from('<HHH', b, 44)
        flash_size = 1 << b[64 - 9]
        cart_form = b[64 - 12]
        print(f"  port      : {self.dev_path}")
        print(f"  device    : EverDrive-N8 PRO (id 0x{self.device:02X})")
        print(f"  serial    : {serial_g:08X}.{serial_l:08X}")
        print(f"  form      : {'FAMICOM' if cart_form else 'NES'}")
        print(f"  os/hw/boot: {sw_ver:04X} / {hw_ver:04X} / {boot_ver:04X}")
        print(f"  flash     : {flash_size >> 20} MiB")
        print(f"  game/boot ctr: {game_ctr} / {boot_ctr}")

    def close(self):
        s, self.port = self.port, None
        if s is None:
            return
        try:
            if self.bridged: self._bridge_close(s)
        except Exception as e:
            sys.stderr.write(f"warning: NESCD bridge close: {e}\n")
        try: s.close()
        except Exception: pass


def main():
    ap = argparse.ArgumentParser(description="EverDrive-N8 PRO USB ROM loader")
    sub = ap.add_subparsers(dest="cmd", required=True)

    r = sub.add_parser("run", help="upload a NES ROM over USB and boot it")
    r.add_argument("rom", help="path to .nes ROM")
    r.add_argument("--fpga", help="optional FPGA core (.rbf) uploaded with CMD_FPG_USB (wipes the menu config)")
    r.add_argument("--rbf", help="FPGA core (.rbf) placed next to the ROM on the SD for the menu to load")
    r.add_argument("port", nargs="?", help="serial port (default: auto-find)")

    i = sub.add_parser("info", help="identify the cart / test the link")
    i.add_argument("port", nargs="?")

    rs = sub.add_parser("reset", help="reboot the cart menu")
    rs.add_argument("port", nargs="?")

    pf = sub.add_parser("put", help="upload a local file to an SD path over USB")
    pf.add_argument("local", help="local file to upload")
    pf.add_argument("sdpath", help="destination path on the SD card (e.g. cheetah/video.bin)")
    pf.add_argument("port", nargs="?")

    gf = sub.add_parser("get", help="download an SD file to a local path over USB")
    gf.add_argument("sdpath", help="file on the SD card (e.g. nespc/system/state)")
    gf.add_argument("local", help="local file to write")
    gf.add_argument("port", nargs="?")

    ls = sub.add_parser("ls", help="list an SD folder over USB")
    ls.add_argument("sdpath", nargs="?", default="/", help="folder on the SD card (default: the root)")
    ls.add_argument("port", nargs="?")

    rm = sub.add_parser("rm", help="delete an SD file or empty folder over USB")
    rm.add_argument("sdpath", help="file on the SD card (e.g. nespc/apps/old.dx)")
    rm.add_argument("port", nargs="?")

    m = sub.add_parser("msg", help="send text to a running edio-style ROM over the USB fifo")
    m.add_argument("text", nargs="?", help="message text ('\\n' escapes become newlines)")
    m.add_argument("--file", help="read the message bytes from a file instead")
    m.add_argument("port", nargs="?")

    anyint = lambda s: int(s, 0)

    mw = sub.add_parser("mem_wr", help="raw mem_wr to a PI-bus address")
    mw.add_argument("addr", type=anyint, help="PI-bus address (e.g. 0x800000 for CHR)")
    mw.add_argument("data", help="bytes as hex string, or @file to read raw bytes")
    mr = sub.add_parser("mem_rd", help="raw mem_rd from a PI-bus address")
    mr.add_argument("addr", type=anyint, help="PI-bus address")
    mr.add_argument("length", type=anyint, help="number of bytes to read")
    for p in (mw, mr):
        p.add_argument("--force", action="store_true",
                       help="allow PRG/SRM PSRAM; crashes a program running from it")
        p.add_argument("port", nargs="?")

    a = ap.parse_args()
    ed = EDN8(getattr(a, "port", None))
    try:
        if a.cmd == "run":
            print(f"EverDrive-N8 PRO on {ed.dev_path}")
            ed.run(a.rom, a.fpga, a.rbf)
        elif a.cmd == "info":
            ed.info()
        elif a.cmd == "reset":
            ed.menu_test(); ed.menu_reset()
            print("menu reset.")
        elif a.cmd == "put":
            ed.put_file(a.local, a.sdpath)
            print(f"uploaded {a.local} -> sd:{a.sdpath}")
        elif a.cmd == "get":
            ed.get_file(a.sdpath, a.local)
            print(f"downloaded sd:{a.sdpath} -> {a.local}")
        elif a.cmd == "ls":
            for name, is_dir, size in ed.dir_list(a.sdpath):
                print(f"{name}/" if is_dir else f"{size:>10}  {name}")
        elif a.cmd == "rm":
            print(f"deleted sd:{a.sdpath}" if ed.file_delete(a.sdpath) else f"sd:{a.sdpath} wasn't there")
        elif a.cmd == "msg":
            if a.file:
                data = open(a.file, "rb").read()
            elif a.text is not None:
                # let the shell pass literal "\n" and have it mean newline
                data = a.text.encode("latin-1").decode("unicode_escape").encode("latin-1")
            else:
                sys.exit("error: give a message string or --file")
            ed.fifo_send(data)
            print(f"sent {len(data)} bytes to the edio fifo on {ed.dev_path}")
        elif a.cmd == "mem_wr":
            if a.data.startswith("@"):
                data = open(a.data[1:], "rb").read()
            else:
                data = bytes.fromhex(a.data)
            ed.mem_wr(a.addr, data, force=a.force)
            print(f"wrote {len(data)} bytes to 0x{a.addr:07X}")
        elif a.cmd == "mem_rd":
            data = ed.mem_rd(a.addr, a.length, force=a.force)
            print(f"read {len(data)} bytes from 0x{a.addr:07X}:")
            print(data.hex())
    finally:
        ed.close()


if __name__ == "__main__":
    main()
