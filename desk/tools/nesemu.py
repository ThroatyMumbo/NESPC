#!/usr/bin/env python3
"""A mapper 773 program in py65 with gfxmodel's bitmap, a minimal PPU, scripted pads and the MCU on a host folder as
the SD card; frames as PNGs."""
import argparse
from collections import deque
from pathlib import Path

from PIL import Image
from py65.devices.mpu6502 import MPU
from py65.memory import ObservableMemory

from cart6502 import Cart
from edmcu import DirCard, Mcu
from gfxmodel import Gfx
from nesgfx import rgb

KBDWORD_READS = 11  # usbadapter/src/kbdword.h
KBDWORD_BYTE3 = (26, 24, 25, 29, 27, 28, 30, 31)
PAST_END = 0x19  # D0, D3, D4 all 1
BENCH_PASS, BENCH_RECORD, NES_HZ = 256, 16, 1789773  # usbadapter/src/bench.h, link.h
BENCH_NAMES = ("down fast", "down table", "up")


def bench_byte(i):
    """bench.h bench_byte: pattern byte i of tests/speedtest's rbaPattern."""
    return ((i * 167 + 29) ^ (i >> 3)) & 0xFF


def bench_reads(mode, b):
    """port.c bench_reads: byte b as 3 $4017 reads (D0 bit 0, D3 bit 3, D4 bit 4) for speedtest's decoder `mode`."""
    bit = [b >> n & 1 for n in range(8)]
    if mode == 0:
        lines = [(bit[1], bit[7], 0), (bit[2], bit[5], bit[6] ^ 1), (bit[0], bit[3], bit[4])]
    else:
        lines = [(bit[0], bit[1], bit[2]), (bit[3], bit[4], bit[5]), (bit[6], bit[7], 0)]
    return [d0 | d3 << 3 | d4 << 4 for d0, d3, d4 in lines]


def kbdstream(w):
    """kbdword.h's kbdstream: the word as the PIO shifts it, 3 bits a read for D3, D4, D0."""
    s = 0
    for r in range(8):
        s |= (w >> 8 + r & 1) << 3 * r | (w >> 16 + r & 1) << 3 * r + 1 | (w >> r & 1) << 3 * r + 2
        s |= (w >> 24 + r & 1) << KBDWORD_BYTE3[r]
    return s
MENU, HOST_PAD = 0x5007, 0x5008
CYCLES_FRAME, CYCLES_VBL = 29781, 2273
BUTTONS = ['right', 'left', 'down', 'up', 'start', 'select', 'b', 'a']
# Family BASIC keyboard by row: $4017 D1-D4 with column 0, then with column 1 (nesdev; kbdtest/kbdtest.s rbaLabels)
KBD_KEYS = ['F8 RET [ ] KNA RSH YEN STP', 'F7 @ : ; _ / - ^', 'F6 O L K . , P 0', 'F5 I U J M N 9 8',
            'F4 Y G H B V 7 6', 'F3 T R D F C 5 4', 'F2 W S A X Z E 3', 'F1 ESC Q CTR LSH GRP 1 2',
            'CLR UP RGT LFT DWN SPC DEL INS']


class Kbd:
    """The keyboard on $4016 OUT0-2 (R, C, K) and $4017 D1-D4; stuck holds an OUT line at a level at the keyboard."""

    def __init__(self, stuck=None, present=True):
        self.stuck = stuck or {}
        self.present = present  # absent, D1-D4 are left to port 2's D3, D4
        self.held = set()
        self.out = self.row = self.col = 0

    def write(self, v):
        for bit, level in self.stuck.items():
            v = v & ~(1 << bit) | level << bit
        c = v >> 1 & 1
        if v & 1:
            self.row = 0
        elif self.out & 2 and not c:
            self.row += 1
        self.col, self.out = c, v

    def read(self, a):
        if not self.present or not self.out & 4:
            return 0x40
        data = 0x1E
        if self.row < len(KBD_KEYS):
            for b, name in enumerate(KBD_KEYS[self.row].split()[self.col * 4:self.col * 4 + 4]):
                if name in self.held:
                    data &= ~(2 << b)
        return 0x40 | data


class Adapter:
    """usbadapter on port 2: one word a strobe in 11 reads of D0, D3 and D4; a read with OUT0 high starts an upstream
    byte, which the link echoes."""

    def __init__(self):
        self.sys = deque()  # SYS_* codes (src/kbdword.h)
        self.queue = deque()
        self.notes = deque()  # (note, velocity), velocity 0 for off
        self.replies = deque()
        self.up = []  # every upstream byte
        self.packet = []
        self.up_bits = None  # the upstream byte coming in: [bits read, value]
        self.seq = 0
        self.dx = self.dy = 0  # mouse motion not yet sent, in NES pixels
        self.wheel = 0  # wheel notches not yet sent, positive down the page
        self.buttons = self.sent_buttons = 0
        self.cur = self.loaded = self.word(0)
        self.pending = False
        self.n = KBDWORD_READS
        self.strobe = 0
        self.clock = lambda: 0  # CPU cycles, for the speed test
        self.stream = None  # a down pass's reads, then stream_pos: -2 before OUT0 rises, -1 before it falls
        self.stream_pos = self.stream_mode = self.stream_t0 = 0
        self.bench = [[0, 0, 0] for _ in BENCH_NAMES]  # cycles, bytes, errors
        self.up_left = self.up_n = self.up_bad = self.up_first = self.up_last = 0

    def word(self, key, tag=0xA0):
        return 0x4B | (tag | self.seq & 15) << 8 | key << 16

    def link(self, b):
        self.up.append(b)
        if self.up_left:
            now = self.clock()
            self.up_first = now if not self.up_n else self.up_first
            self.up_last = now
            self.up_bad += b != bench_byte(self.up_n & 255)
            self.up_n += 1
            self.up_left -= 1
            if not self.up_left:
                s = self.bench[2]
                s[0] += self.up_last - self.up_first
                s[1] += self.up_n - 1
                s[2] += self.up_bad
            return
        self.packet.append(b)
        if len(self.packet) >= 2 and len(self.packet) == 2 + self.packet[1]:
            if self.packet[0] == 0x01:
                self.replies.extend(self.packet[2:])
            elif self.packet[0] == 0x03:
                self.bench_cmd(self.packet[2:])
            self.packet = []

    def bench_cmd(self, p):
        """link.c bench: a down pass armed, an up burst armed, or the records of a report."""
        if p[0] == 0:
            self.stream_mode = p[1]
            self.stream = [v for i in range(BENCH_PASS) for v in bench_reads(p[1], bench_byte(i) ^ p[2])]
            self.stream_pos = -2
        elif p[0] == 1:
            self.up_left, self.up_n, self.up_bad = p[1] | p[2] << 8, 0, 0
        elif p[0] == 2:
            nes = (p[1] | p[2] << 8, p[3] | p[4] << 8, 0)
            for t, (cycles, n, err) in enumerate(self.bench):
                err = min(err + nes[t], 999999)
                if cycles and n:
                    s = f"{min(n * NES_HZ / cycles / 1000, 999.9):5.1f}{min(cycles / n, 999.9):5.1f}{err:6d}"
                else:
                    s = f"  ---  ---{err:6d}"
                print(f"bench: {BENCH_NAMES[t]}: {n} bytes in {cycles} cycles: {s}")
                self.replies.extend(s.encode())
            self.bench = [[0, 0, 0] for _ in BENCH_NAMES]

    def stream_read(self):
        if self.stream_pos < 0:
            return 0
        if self.stream_pos == 0:
            self.stream_t0 = self.clock()
        v = self.stream[self.stream_pos]
        self.stream_pos += 1
        if self.stream_pos == len(self.stream):
            s = self.bench[self.stream_mode]
            s[0] += self.clock() - self.stream_t0
            s[1] += BENCH_PASS
            self.stream = None
            self.n, self.loaded = KBDWORD_READS, self.cur
        return v

    def mouse_word(self):
        dx, dy = (max(-63, min(63, d)) for d in (self.dx, self.dy))
        self.dx -= dx
        self.dy -= dy
        self.sent_buttons = b = self.buttons
        return (0x4B | (0xB0 | self.seq & 15) << 8 | ((b & 1) << 7 | dx & 0x7F) << 16
                | ((b >> 1 & 1) << 7 | dy & 0x7F) << 24)

    def serve(self):
        # popped once a read of it ends: system requests, keys, MIDI notes, link replies, the wheel, then motion
        if self.pending:
            return
        if self.sys:
            self.seq += 1
            self.cur, self.pending = self.word(self.sys.popleft(), 0xE0), True
        elif self.queue:
            self.seq += 1
            self.cur, self.pending = self.word(self.queue.popleft()), True
        elif self.notes:
            self.seq += 1
            note, vel = self.notes.popleft()
            self.cur, self.pending = self.word((vel > 0) << 7 | note | vel << 8, 0xD0), True
        elif self.replies:
            self.seq += 1
            self.cur, self.pending = self.word(self.replies.popleft(), 0xC0), True
        elif self.wheel:
            self.seq += 1
            n = max(-127, min(127, self.wheel))
            self.wheel -= n
            self.cur, self.pending = self.word(n & 0xFF, 0x80), True
        elif self.dx or self.dy or self.buttons != self.sent_buttons:
            self.seq += 1
            self.cur, self.pending = self.mouse_word(), True

    def write(self, v):
        if self.stream is not None:
            if self.stream_pos == -2 and v & 1 or self.stream_pos == -1 and not v & 1:
                self.stream_pos += 1
            self.strobe = v & 1
            return
        if v & 1 and self.up_bits is None:
            self.loaded, self.n = self.cur, 0
        self.strobe = v & 1
        self.serve()

    def read(self):
        if self.stream is not None:
            return self.stream_read()
        if self.up_bits is not None:
            self.up_bits[1] |= self.strobe << self.up_bits[0]
            self.up_bits[0] += 1
            if self.up_bits[0] == 8:
                self.link(self.up_bits[1])
                self.up_bits = None
                self.n = 0 if self.strobe else KBDWORD_READS  # the PIO is idle until the next strobe
                self.loaded = self.cur
            return 1
        if self.strobe:
            self.up_bits = [0, 0]
            return self.lines(0)
        if self.n >= KBDWORD_READS:
            return PAST_END
        v = self.lines(self.n)
        self.n += 1
        if self.n == KBDWORD_READS and self.loaded == self.cur and self.pending:
            self.cur, self.pending = self.word(0), False
        self.serve()
        return v

    def lines(self, r):
        """$4017's D0 (bit 0), D3 (bit 3) and D4 (bit 4) in read r of the loaded word."""
        g = kbdstream(self.loaded) >> 3 * r & 7
        return (g & 1) << 3 | (g >> 1 & 1) << 4 | g >> 2 & 1


class Pad2:
    """A standard pad on port 2 with buttons held, to check the adapter's word is not mistaken for it."""

    def __init__(self, buttons):
        self.buttons = buttons
        self.shift = 0

    def write(self, v):
        if v & 1:
            self.shift = self.buttons | 0xFF00

    def read(self):
        bit = self.shift & 1
        self.shift = self.shift >> 1 | 0x8000
        return bit


# scancode set 2 (nes/src/keyboard/ps2.s rbaPlain/rbaShift): make code -> unshifted, shifted
PS2_SET2 = {0x0E: '`~', 0x16: '1!', 0x1E: '2@', 0x26: '3#', 0x25: '4$', 0x2E: '5%', 0x36: '6^', 0x3D: '7&',
            0x3E: '8*', 0x46: '9(', 0x45: '0)', 0x4E: '-_', 0x55: '=+', 0x66: '\b\b', 0x0D: '\t\t', 0x15: 'qQ',
            0x1D: 'wW', 0x24: 'eE', 0x2D: 'rR', 0x2C: 'tT', 0x35: 'yY', 0x3C: 'uU', 0x43: 'iI', 0x44: 'oO',
            0x4D: 'pP', 0x54: '[{', 0x5B: ']}', 0x5D: '\\|', 0x1C: 'aA', 0x1B: 'sS', 0x23: 'dD', 0x2B: 'fF',
            0x34: 'gG', 0x33: 'hH', 0x3B: 'jJ', 0x42: 'kK', 0x4B: 'lL', 0x4C: ';:', 0x52: '\'"', 0x5A: '\r\r',
            0x1A: 'zZ', 0x22: 'xX', 0x21: 'cC', 0x2A: 'vV', 0x32: 'bB', 0x31: 'nN', 0x3A: 'mM', 0x41: ',<',
            0x49: '.>', 0x4A: '/?', 0x29: '  ', 0x76: '\x1b\x1b'}


def ps2_codes(text):
    """Make and break codes typing text on a US PS/2 keyboard, shift held round the shifted characters."""
    out = []
    for ch in text:
        for code, (lo, hi) in PS2_SET2.items():
            if ch == lo:
                out += [code, 0xF0, code]
                break
            if ch == hi:
                out += [0x12, code, 0xF0, code, 0xF0, 0x12]
                break
        else:
            raise SystemExit(f"--ps2: no key types {ch!r}")
    return out


class Ps2:
    """A PS/2 keyboard on port 1, DATA on D3 and CLK on D4 (read inverted), CLK held low through a diode while OUT0
    is low; a byte cut off before its 11th falling edge is sent again at the next release."""
    P, H = 143, 72          # cycles a bit at 12.5 kHz, CLK high for the first half
    DELAY, GAP = 179, 358   # 100 us from a release to the start bit, 200 us between bytes

    def __init__(self, now):
        self.now = now
        self.queue = deque()
        self.out0 = 0
        self.start = None  # cycle the frame in flight starts at
        self.sent = 0

    @staticmethod
    def bits(b):
        return [0] + [b >> i & 1 for i in range(8)] + [1 ^ bin(b).count('1') & 1, 1]

    def advance(self, t):
        while self.start is not None and t >= self.start + 11 * self.P:
            self.queue.popleft()
            self.sent += 1
            self.start = self.start + 11 * self.P + self.GAP if self.queue else None

    def write(self, v):
        t = self.now()
        self.advance(t)
        out0 = v & 1
        if out0 and not self.out0 and self.queue:
            self.start = t + self.DELAY
        elif not out0 and self.out0:
            if self.start is not None and t >= self.start + 10 * self.P + self.H:
                self.queue.popleft()
                self.sent += 1
            self.start = None
        self.out0 = out0

    def read(self):
        t = self.now()
        self.advance(t)
        clk = data = 1
        if not self.out0:
            clk = 0
        elif self.start is not None and t >= self.start:
            i, phase = divmod(t - self.start, self.P)
            clk = int(phase < self.H)
            data = self.bits(self.queue[0])[i]
        return (0 if data else 0x08) | (0 if clk else 0x10)


def plugin(path, name):
    """class name of an app core's .py: Gfx with gfxmodel.Gfx's write, read and frame; Mapper(nes, mem)"""
    import importlib.util
    spec = importlib.util.spec_from_file_location(Path(path).stem, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return getattr(mod, name)


class Nes(Cart):
    def __init__(self, prg, stuck=None, port2=None, ps2=False, kbd=True, mapper=None, sd=None, gfx_model=None):
        m = ObservableMemory()
        prg = open(prg, 'rb').read()
        self.image = prg[:0x8000]
        # first: a mapper's writes into $8000-$BFFF see the value before Cart keeps the ROM's
        self.mapper = plugin(mapper, 'Mapper')(self, m) if mapper else None
        super().__init__(m, prg)
        self.gfx = plugin(gfx_model, 'Gfx')() if gfx_model else Gfx()
        self.trace = None  # sim/tb_fb script lines of every blitter access, the CPU cycles between them as "d n"
        self.trace_at = 0
        m.subscribe_to_write(range(0x5020, 0x5035), self._gfx_wr)
        m.subscribe_to_read([0x502E], self._gfx_rd)
        if not mapper and not gfx_model:
            m.subscribe_to_write(range(0x5800, 0x6000), self._gfx_wr)
            m.subscribe_to_read(range(0x5800, 0x6000), self._gfx_rd)
        if sd:
            self.attach(Mcu(DirCard(sd), rtc=(0x26, 0x10, 0x16, 0x12, 0x34, 0x56)))
        self.pad = 0
        self.shift = 0
        m.subscribe_to_read([HOST_PAD], lambda a: 0)
        self.menu_at = None  # the frame the program wrote $5007, handing the cart back to the menu
        m.subscribe_to_write([MENU], lambda a, v: setattr(self, 'menu_at', self.frames))
        m.subscribe_to_write([0x4016], self._strobe)
        self.ps2 = Ps2(lambda: self.mpu.processorCycles) if ps2 else None
        m.subscribe_to_read([0x4016], lambda a: self._pad_bit(a) | (self.ps2.read() if self.ps2 else 0))
        self.kbd = Kbd(stuck, kbd)
        self.port2 = port2
        m.subscribe_to_read([0x4017], lambda a: self.kbd.read(a) | (self.port2.read() if self.port2 else 0))
        # PPU
        self.ctrl = self.status = self.mask = 0
        self.vaddr = 0
        self.latch = 0
        self.oam_addr = 0
        self.oam = bytearray(256)
        self.vram = bytearray(0x4000)
        self.palette = bytearray(32)
        m.subscribe_to_write(range(0x2000, 0x4000), self._ppu_wr)
        m.subscribe_to_read(range(0x2000, 0x4000), self._ppu_rd)
        m.subscribe_to_write([0x4014], self._dma)
        self.mpu = MPU(memory=m)
        self.mpu.pc = m[0xFFFC] | m[0xFFFD] << 8
        self.frames = 0
        self.nmi_pending = False

    def _gap(self):
        now = self.mpu.processorCycles
        if self.trace is not None and now - self.trace_at > 1:
            self.trace.append(f"d {now - self.trace_at - 1:x}")
        self.trace_at = now

    def _gfx_wr(self, a, v):
        self._gap()
        if self.trace is not None:
            self.trace.append(f"w {a:04x} {v:02x}")
        self.gfx.write(a, v)
        return None

    def _gfx_rd(self, a):
        self._gap()
        if self.trace is not None:
            self.trace.append("p" if a == 0x502E else f"r {a:04x}")
        return self.gfx.read(a)

    def _strobe(self, a, v):
        if v & 1:
            self.shift = self.pad
        self.kbd.write(v)
        if self.port2:
            self.port2.write(v)
        if self.ps2:
            self.ps2.write(v)
        return None

    def _pad_bit(self, a):
        bit = (self.shift >> 7) & 1  # A first, as BUTTONS' bit 7
        self.shift = (self.shift << 1) & 0xFF
        return bit

    def _ppu_wr(self, a, v):
        r = a & 7
        if r == 0:
            if v & 0x80 and not self.ctrl & 0x80 and self.status & 0x80:
                self.nmi_pending = True  # NMI turned on within vblank: the PPU raises it at once
            self.ctrl = v
        elif r == 1:
            self.mask = v
        elif r == 3:
            self.oam_addr = v
        elif r == 4:
            self.oam[self.oam_addr] = v
            self.oam_addr = (self.oam_addr + 1) & 0xFF
        elif r == 5:
            self.latch ^= 1
        elif r == 6:
            self.vaddr = ((v & 0x3F) << 8) if not self.latch else (self.vaddr & 0xFF00) | v
            self.latch ^= 1
        elif r == 7:
            va = self.vaddr & 0x3FFF
            if va >= 0x3F00:
                i = va & 0x1F
                if i & 3 == 0:
                    i &= 0x0F
                self.palette[i] = v & 0x3F
            elif va < 0x2000 and va & 0x1000:
                self.vram[va] = v
            self.vaddr = (self.vaddr + (32 if self.ctrl & 4 else 1)) & 0x3FFF
        return None

    def _ppu_rd(self, a):
        if a & 7 == 2:
            s = self.status
            self.status &= 0x7F
            self.latch = 0
            return s
        return 0

    def _dma(self, a, v):
        s = self.mem._subject
        for i in range(256):
            self.oam[(self.oam_addr + i) & 0xFF] = s[v << 8 | i]
        return None

    def run_cycles(self, n):
        mpu = self.mpu
        end = mpu.processorCycles + n
        while mpu.processorCycles < end:
            mpu.step()
            if self.nmi_pending:
                self.nmi_pending = False
                mpu.nmi()

    def frame(self):
        """One frame: the visible lines, then vblank with its NMI."""
        self.run_cycles(CYCLES_FRAME - CYCLES_VBL)
        self.status |= 0x80
        if self.ctrl & 0x80:
            self.mpu.nmi()
        self.run_cycles(CYCLES_VBL)
        self.status &= 0x7F
        self.frames += 1

    def render(self):
        g, pal = self.gfx, self.palette
        bg = g.frame()
        out = [[pal[0]] * 256 for _ in range(240)]
        opaque = [[False] * 256 for _ in range(240)]
        for y in range(240 if self.mask & 0x08 else 0):
            for x in range(256):
                v = bg[y][x]
                if v & 3:
                    out[y][x] = pal[(v >> 2) * 4 + (v & 3)]
                    opaque[y][x] = True
        for s in range(63, -1, -1):
            sy, t, at, sx = self.oam[s * 4:s * 4 + 4]
            for r in range(8):
                y = sy + 1 + r
                if y >= 240:
                    continue
                row = 7 - r if at & 0x80 else r
                lo = self.vram[0x1000 + t * 16 + row]
                hi = self.vram[0x1000 + t * 16 + 8 + row]
                for c in range(8):
                    x = sx + c
                    if x >= 256:
                        continue
                    b = c if at & 0x40 else 7 - c
                    v = ((lo >> b) & 1) | ((hi >> b) & 1) << 1
                    if v and not (at & 0x20 and opaque[y][x]):
                        out[y][x] = pal[0x10 + (at & 3) * 4 + v]
        im = Image.new("RGB", (256, 240))
        im.putdata([rgb(c) for row in out for c in row])
        return im


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('prg', help="the PRG image (build/*.prg), banks past 32 KiB as $5010 maps them")
    ap.add_argument('--sd', help="a directory as the SD card, for the MCU's listings, reads and writes")
    ap.add_argument('--mapper', help="a .py whose Mapper class models the app core's own registers")
    ap.add_argument('--gfx-model', help="a .py whose Gfx class models the app core's drawing in place of gfxmodel's")
    ap.add_argument('--frames', type=int, default=60)
    ap.add_argument('--press', action='append', default=[],
                    help="frame:button[+button]:hold, pad 1 held from that frame")
    ap.add_argument('--key', action='append', default=[],
                    help="frame:key[+key]:hold, Family BASIC keys (as KBD_KEYS names them) held from that frame")
    ap.add_argument('--stuck', action='append', default=[], help="outN=0|1, that $4016 line stuck at the keyboard")
    ap.add_argument('--type', action='append', default=[],
                    help="frame:text, typed into the usbadapter on port 2 at that frame (\\r, \\x1b escapes)")
    ap.add_argument('--pad2', type=lambda s: int(s, 0), help="a standard pad on port 2 holding these buttons")
    ap.add_argument('--adapter', action='store_true', help="the usbadapter on port 2, even with nothing typed")
    ap.add_argument('--mouse', action='append', default=[],
                    help="frame:dx,dy[:buttons], the adapter's mouse moved by that many NES pixels at that frame, "
                         "buttons (1 left, 2 right) held from then on")
    ap.add_argument('--wheel', action='append', default=[],
                    help="frame:notches, the adapter's mouse wheel turned at that frame (positive down the page)")
    ap.add_argument('--midi', action='append', default=[],
                    help="frame:note[:velocity], a MIDI keyboard on the adapter plays that note at that frame "
                         "(velocity 100 by default, 0 for note off)")
    ap.add_argument('--sys', action='append', default=[],
                    help="frame[:code], a system request from the adapter at that frame (1, Alt+F4, by default)")
    ap.add_argument('--apu-log', action='store_true', help="print the APU register writes")
    ap.add_argument('--ps2', action='append', default=[],
                    help="frame:text, typed on a PS/2 keyboard on port 1 at that frame (\\r, \\x1b escapes)")
    ap.add_argument('--ps2-codes', action='append', default=[],
                    help="frame:hex,hex,..., raw scancodes from the port 1 PS/2 keyboard at that frame (e0,75 = up)")
    ap.add_argument('--shot', action='append', default=[], help="frame:out.png, the screen at the end of that frame")
    ap.add_argument('--scale', type=int, default=3)
    ap.add_argument('--trace', help="write the blitter accesses as a sim/tb_fb script")
    a = ap.parse_args()
    stuck = {int(s.split('=')[0].removeprefix('out')): int(s.split('=')[1]) for s in a.stuck}
    typed = {}
    for t in a.type:
        f, text = t.split(':', 1)
        typed[int(f)] = text.encode('latin-1').decode('unicode_escape').encode('latin-1')
    moves = {}
    for m in a.mouse:
        f, d, *b = m.split(':')
        dx, dy = (int(v) for v in d.split(','))
        moves[int(f)] = (dx, dy, int(b[0], 0) if b else None)
    wheels = {}
    for w in a.wheel:
        f, n = w.split(':')
        wheels[int(f)] = wheels.get(int(f), 0) + int(n)
    notes = {}
    for n in a.midi:
        f, note, *v = n.split(':')
        notes.setdefault(int(f), []).append((int(note, 0), int(v[0], 0) if v else 100))
    sysreq = {}
    for s in a.sys:
        f, *code = s.split(':')
        sysreq.setdefault(int(f), []).append(int(code[0], 0) if code else 1)
    port2 = (Pad2(a.pad2) if a.pad2 is not None
             else Adapter() if typed or moves or wheels or notes or sysreq or a.adapter else None)
    ps2 = {}
    for t in a.ps2:
        f, text = t.split(':', 1)
        ps2.setdefault(int(f), []).extend(ps2_codes(text.encode('latin-1').decode('unicode_escape')))
    for t in a.ps2_codes:
        f, codes = t.split(':', 1)
        ps2.setdefault(int(f), []).extend(int(c, 16) for c in codes.split(','))
    nes = Nes(a.prg, stuck, port2, bool(ps2), bool(a.key or a.stuck), a.mapper, a.sd, a.gfx_model)
    if isinstance(port2, Adapter):
        port2.clock = lambda: nes.mpu.processorCycles
    if a.trace:
        nes.trace = []
    if a.apu_log:
        nes.mem.subscribe_to_write([*range(0x4000, 0x4014), 0x4015],
                                   lambda adr, v: print(f"frame {nes.frames}: ${adr:04x} = ${v:02x}"))
    presses = []
    for p in a.press:
        f, b, n = p.split(':')
        presses.append((int(f), sum(1 << BUTTONS.index(x) for x in b.split('+')), int(n)))
    names = set(' '.join(KBD_KEYS).split())
    keys = []
    for p in a.key:
        f, rest = p.split(':', 1)  # the ':' key is a name too
        k, n = rest.rsplit(':', 1)
        held = set(k.upper().split('+'))
        if held - names:
            ap.error(f"no key {sorted(held - names)}; keys are {' '.join(KBD_KEYS)}")
        keys.append((int(f), held, int(n)))
    shots = {int(s.split(':')[0]): s.split(':', 1)[1] for s in a.shot}
    for f in range(a.frames):
        nes.pad = 0
        for start, bits, n in presses:
            if start <= f < start + n:
                nes.pad |= bits
        nes.kbd.held = {k for start, held, n in keys if start <= f < start + n for k in held}
        if f in typed:
            port2.queue.extend(typed[f])
        if f in notes:
            port2.notes.extend(notes[f])
        if f in sysreq:
            port2.sys.extend(sysreq[f])
        if f in ps2:
            nes.ps2.queue.extend(ps2[f])
        if f in moves:
            dx, dy, b = moves[f]
            port2.dx += dx
            port2.dy += dy
            if b is not None:
                port2.buttons = b
        if f in wheels:
            port2.wheel += wheels[f]
        nes.frame()
        if f in shots:
            im = nes.render()
            im.resize((256 * a.scale, 240 * a.scale), Image.Resampling.NEAREST).save(shots[f])
            print(f"frame {f}: {shots[f]}")
        if nes.menu_at is not None:
            print(f"menu return at frame {nes.menu_at}")
            break
    if a.trace:
        open(a.trace, "w").write("\n".join(nes.trace + ["p", "f"]) + "\n")
    if nes.ps2:
        print(f"ps2: {nes.ps2.sent} bytes sent, {len(nes.ps2.queue)} waiting")
    if isinstance(port2, Adapter) and port2.up:
        print(f"adapter: {len(port2.up)} bytes up, {len(port2.replies)} replies waiting; first {bytes(port2.up[:12]).hex(' ')}")


if __name__ == '__main__':
    main()
