"""The EverDrive N8 Pro MCU's commands as Desk's edio.s sends them, on a card held in memory or a host folder."""
import collections
import struct
from pathlib import Path

FA_READ, FA_WRITE, FA_CREATE_NEW, FA_CREATE_ALWAYS, FA_OPEN_ALWAYS = 0x01, 0x02, 0x04, 0x08, 0x10
FR_NO_FILE, FR_NO_PATH, FR_DENIED, FR_EXIST, FR_INVALID_OBJECT = 4, 5, 7, 8, 9
DIR_GET_MAX = 32  # the MCU answers a longer ED_F_DIR_GET with 0x82 (edio.inc)


class MemCard:
    """A card in memory: sd, {MCU path: bytes}; dirs, folders no file's path makes; readonly, paths a delete is denied."""

    def __init__(self):
        self.sd = {}
        self.dirs = {b'nespc/system'}  # every card Desk runs from has it
        self.readonly = set()

    def is_dir(self, p):
        return p == b'' or p in self.dirs or any(k.startswith(p + b'/') for k in [*self.sd, *self.dirs])

    def is_file(self, p):
        return p in self.sd

    def children(self, p):
        """[(path, name, is a folder)] in p, as the MCU sorts them: folders first, then by name in any case"""
        pre, out = p + b'/' if p else b'', {}
        for k in [*self.sd, *self.dirs]:
            if k.startswith(pre) and k != p:
                head, sep, _ = k[len(pre):].partition(b'/')
                out[head] = out.get(head, False) or bool(sep) or k in self.dirs
        return sorted(((pre + n, n, d) for n, d in out.items()), key=lambda e: (not e[2], e[1].lower()))

    def read(self, p):
        return self.sd[p]

    def write(self, p, data):
        self.sd[p] = bytes(data)

    def mkdir(self, p):
        self.dirs.add(p)

    def delete(self, p):
        if p in self.readonly:
            return FR_DENIED
        if p in self.sd:
            del self.sd[p]
            self.dirs.update(p[:i] for i in range(len(p)) if p[i:i + 1] == b'/')  # FAT keeps the folders
            return 0
        if p and self.is_dir(p):
            if self.children(p):
                return FR_DENIED
            self.dirs.discard(p)
            return 0
        return FR_NO_FILE


class DirCard:
    """A host folder as the card; without one, the current folder, read only."""

    def __init__(self, root):
        self.root = Path(root or '.')
        self.writable = root is not None

    def _p(self, p):
        return self.root / p.decode('latin-1')

    def _writes(self):
        if not self.writable:
            raise AssertionError("the program writes the SD card: give --sd")

    def is_dir(self, p):
        return self._p(p).is_dir()

    def is_file(self, p):
        return self._p(p).is_file()

    def children(self, p):
        qs = sorted(self._p(p).iterdir(), key=lambda q: (not q.is_dir(), q.name.lower()))
        pre = p + b'/' if p else b''
        return [(pre + q.name.encode('latin-1'), q.name.encode('latin-1'), q.is_dir()) for q in qs]

    def read(self, p):
        return self._p(p).read_bytes()

    def write(self, p, data):
        self._writes()
        q = self._p(p)
        q.parent.mkdir(parents=True, exist_ok=True)
        q.write_bytes(data)

    def mkdir(self, p):
        self._writes()
        self._p(p).mkdir()

    def delete(self, p):
        q = self._p(p)
        if not (q.is_file() or q.is_dir() and q != self.root):
            return FR_NO_FILE
        self._writes()
        if q.is_dir() and any(q.iterdir()):
            return FR_DENIED
        q.rmdir() if q.is_dir() else q.unlink()
        return 0


class Mcu:
    """The MCU's commands edio.s uses on card, one file open at a time as the MCU has one handle; USB writes are kept in
    usb."""

    def __init__(self, card=None, rtc=(0x26, 0x10, 0x10, 0x12, 0x34, 0x56)):
        self.card = card or MemCard()
        self.cur = None  # the open file's bytes
        self.open_path = None
        self.cur_path = None  # the path written back on close, when open for writing
        self.listing = []  # the loaded directory: (path, name, is a folder)
        self.tx = collections.deque()
        self.status = 0
        self.mode = 0
        self.pos = 0
        self.opens = self.seeks = 0
        self.usb = bytearray()  # what USB_WR sent the host
        self.rtc = list(rtc)  # BCD, as ED_RTC_GET sends it
        self.boot_ctr = 1  # SYS_INF's power-on count
        self.proto = self._proto()
        next(self.proto)

    sd = property(lambda self: self.card.sd, lambda self, v: setattr(self.card, 'sd', v))
    dirs = property(lambda self: self.card.dirs, lambda self, v: setattr(self.card, 'dirs', v))
    readonly = property(lambda self: self.card.readonly, lambda self, v: setattr(self.card, 'readonly', v))

    def is_dir(self, p):
        return self.card.is_dir(p)

    def children(self, p):
        return self.card.children(p)

    def rx(self, b):
        self.proto.send(b)

    def _u(self, n):
        v = 0
        for i in range(n):
            v |= (yield) << (8 * i)
        return v

    def _bytes(self, n):
        out = bytearray()
        for _ in range(n):
            out.append((yield))
        return bytes(out)

    def _path(self):
        return (yield from self._bytes((yield from self._u(2)))).strip(b'/')

    def rec(self, path, name, is_dir, maxlen):
        """ed_dir_rec's record: status, size, date, time, attribute, name length, name"""
        name = name[:maxlen]
        size = 0 if is_dir else len(self.card.read(path))
        return struct.pack('<BI4xBH', 0, size, 0x10 if is_dir else 0x20, len(name)) + name

    def _proto(self):
        card = self.card
        while True:
            if (yield) != ord('+') or (yield) != ord('+') ^ 0xff:
                continue
            cmd = yield
            if (yield) != cmd ^ 0xff:
                continue
            if cmd == 0x10:
                self.tx += [self.status, 0xa5]
            elif cmd == 0x14:
                self.tx += self.rtc
            elif cmd == 0x15:
                self.rtc = list((yield from self._bytes(6)))
            elif cmd == 0x26:
                self.tx += bytes(28) + self.boot_ctr.to_bytes(4, 'little') + bytes(32)
            elif cmd == 0xc5:
                yield  # options: sorted
                path = yield from self._path()
                self.listing = card.children(path) if card.is_dir(path) else []
                self.status = 0 if card.is_dir(path) else FR_NO_PATH
            elif cmd == 0xc6:
                self.tx += len(self.listing).to_bytes(2, 'little')
            elif cmd == 0xc8:
                first, count, maxlen = (yield from self._u(2)), (yield from self._u(2)), (yield from self._u(2))
                if count > DIR_GET_MAX:
                    self.tx.append(0x82)
                    continue
                for p, name, d in self.listing[first:first + count]:
                    self.tx += self.rec(p, name, d, maxlen)
            elif cmd == 0xc9:
                mode = yield
                path = yield from self._path()
                if self.mode:
                    raise AssertionError(f'FOPN of {path} with {self.open_path} still open')
                self.cur_path = None
                self.opens += 1
                parent = path.rpartition(b'/')[0]
                if card.is_file(path) and mode == FA_READ:
                    self.cur = bytearray(card.read(path))
                    self.mode, self.pos, self.status, self.open_path = mode, 0, 0, path
                elif mode & FA_WRITE and parent and not card.is_dir(parent):
                    self.status = FR_NO_PATH
                elif mode == FA_WRITE | FA_CREATE_ALWAYS:
                    self.cur, self.cur_path = bytearray(), path
                    self.mode, self.pos, self.status, self.open_path = mode, 0, 0, path
                elif mode == FA_WRITE | FA_OPEN_ALWAYS or (mode == FA_WRITE and card.is_file(path)):
                    self.cur, self.cur_path = bytearray(card.read(path) if card.is_file(path) else b''), path
                    self.mode, self.pos, self.status, self.open_path = mode, 0, 0, path
                else:
                    self.status = FR_NO_FILE
            elif cmd == 0xcf:
                off = yield from self._u(4)
                self.pos = off
                self.seeks += 1
                self.status = 0 if self.mode and off <= len(self.cur) else FR_INVALID_OBJECT
            elif cmd == 0xca:
                n = yield from self._u(4)
                if n > 512:
                    raise AssertionError(f'FRD of {n} bytes')
                if not self.mode & FA_READ:
                    self.tx.append(FR_INVALID_OBJECT)
                    continue
                if self.pos + n > len(self.cur):
                    raise AssertionError(f'FRD of {n} bytes at {self.pos}, past the end of {len(self.cur)}')
                data = self.cur[self.pos:self.pos + n]
                self.tx.append(0)
                self.tx += data
                self.pos += len(data)
            elif cmd == 0xcc:
                n = yield from self._u(4)
                self.status = 0
                while n:
                    block = min(n, 1024)
                    if not self.mode & FA_WRITE:
                        self.tx.append(FR_DENIED)
                        self.status = FR_DENIED
                        break
                    self.tx.append(0)
                    data = yield from self._bytes(block)
                    self.cur[self.pos:self.pos + block] = data
                    self.pos += block
                    n -= block
            elif cmd == 0xce:
                self.status = 0 if self.mode else FR_INVALID_OBJECT
                if self.cur_path is not None:
                    card.write(self.cur_path, self.cur)
                    self.cur_path = None
                self.mode, self.open_path = 0, None
            elif cmd == 0xd2:
                path = yield from self._path()
                parent = path.rpartition(b'/')[0]
                if card.is_dir(path) or card.is_file(path):
                    self.status = FR_EXIST
                elif parent and not card.is_dir(parent):
                    self.status = FR_NO_PATH
                else:
                    card.mkdir(path)
                    self.status = 0
            elif cmd == 0xd3:
                path = yield from self._path()
                if path == self.open_path:
                    raise AssertionError(f'deleted {path} while it was open')
                self.status = card.delete(path)
            elif cmd == 0xd6:
                # as the cart answers: a file only, into an existing folder
                mode = yield
                src, dst = (yield from self._path()), (yield from self._path())
                if self.mode:
                    raise AssertionError(f'FCP of {src} with {self.open_path} still open')
                parent = dst.rpartition(b'/')[0]
                if not card.is_file(src):
                    self.status = FR_NO_FILE
                elif parent and not card.is_dir(parent):
                    self.status = FR_NO_PATH
                elif mode & FA_CREATE_NEW and (card.is_file(dst) or card.is_dir(dst)):
                    self.status = FR_EXIST
                elif not mode & FA_WRITE:
                    card.write(dst, b'')
                    self.status = FR_DENIED
                else:
                    card.write(dst, card.read(src))
                    self.status = 0
            elif cmd == 0x19:
                addr = yield from self._u(4)
                n = yield from self._u(4)
                yield  # ack
                self.tx += bytes(n)
            elif cmd == 0xd0:
                path = yield from self._path()
                name = path.rsplit(b'/', 1)[-1]
                if card.is_file(path) or path and card.is_dir(path):
                    self.tx += self.rec(path, name, not card.is_file(path), 255)
                else:
                    self.tx.append(FR_NO_FILE)
            elif cmd == 0x22:
                n = yield from self._u(2)
                self.usb += yield from self._bytes(n)
            else:
                raise AssertionError(f'unexpected MCU command {cmd:#04x}')
