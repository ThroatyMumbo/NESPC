#!/usr/bin/env python3
"""Reference model of mapper 773's bitmap and blitter (rtl/fb.sv, rtl/blit.sv), and a test that runs the same random
script through it and through a Verilator testbench of them (--sim), comparing every frame and read."""
import argparse
import random
import subprocess
import sys
from pathlib import Path

REG = 0x5020
DX, DY, W, H, SX, SY, FG, BG, KEY, FLAGS, CX0, CY0, CX1, CY1, OP, DATA = range(REG, REG + 16)
WIN_REG, WIN = 0x5030, 0x5800
MX0, MY0, MX1, MY1 = range(0x5031, 0x5035)
OP_FILL, OP_COPY, OP_EXPAND, OP_IMAGE, OP_PAL = 1, 2, 3, 4, 5
F_BG_CLEAR, F_KEY, F_XOR, F_OVER, F_PAL = 1, 2, 4, 8, 16
SW, SH = 256, 240


class Gfx:
    def __init__(self):
        self.pix = [[0] * SW for _ in range(SH)]
        self.pal = [[0] * 32 for _ in range(SH)]
        self.r = {DX: 0, DY: 0, W: 0, H: 0, SX: 0, SY: 0, FG: 0, BG: 0, KEY: 0, FLAGS: 0,
                  CX0: 0, CY0: 0, CX1: 0, CY1: 240, MX0: 0, MY0: 0, MX1: 0, MY1: 0}
        self.win = 0
        self.stream = None

    def write(self, a, d):
        if WIN <= a < WIN + 0x800:
            self.win_write((self.win << 11) | (a & 0x7FF), d)
        elif a == WIN_REG:
            self.win = d & 15
        elif a == OP:
            if self.stream is None and OP_FILL <= d & 7 <= OP_PAL:
                self.start(d & 7)
        elif a == DATA:
            if self.stream is not None:
                self.feed(d)
        elif a in self.r:
            self.r[a] = d

    def read(self, a):
        if WIN <= a < WIN + 0x800:
            u = (self.win << 11) | (a & 0x7FF)
            if u < 0x3C00:
                span, plane = u >> 1, u & 1
                y, x0 = span >> 5, (span & 31) * 8
                return sum(((self.pix[y][x0 + i] >> plane) & 1) << (7 - i) for i in range(8))
            if 0x4000 <= u < 0x5E00:
                s = u - 0x4000
                return self.pal[s >> 5][s & 31]
            return 0xFF
        if a == OP:
            return 0x80 if self.stream is not None else 0
        raise ValueError(f"no read at {a:04x}")

    def win_write(self, u, d):
        if u < 0x3C00:
            span, plane = u >> 1, u & 1
            y, x0 = span >> 5, (span & 31) * 8
            for i in range(8):
                b = (d >> (7 - i)) & 1
                self.pix[y][x0 + i] = (self.pix[y][x0 + i] & ~(1 << plane)) | (b << plane)
        elif 0x4000 <= u < 0x5E00:
            s = u - 0x4000
            self.pal[s >> 5][s & 31] = d & 3

    def geometry(self):
        r = self.r
        w = r[W] or 256
        h = r[H] or 256
        return w, h

    def row_ok(self, y):
        r = self.r
        return y < SH and y >= r[CY0] and (r[CY1] == 0 or y < r[CY1])

    def mask_row(self, y):
        r = self.r
        return not r[FLAGS] & F_OVER and r[MX0] != r[MX1] and y >= r[MY0] and (r[MY1] == 0 or y < r[MY1])

    def masked(self, y, x0, x1):
        """Pixels x0 to x1 (inclusive) on row y touch the mask."""
        r = self.r
        return self.mask_row(y) and x1 >= r[MX0] and (r[MX1] == 0 or x0 < r[MX1])

    def xs(self, y):
        r = self.r
        w, _ = self.geometry()
        for x in range(r[DX], min(r[DX] + w, 256)):
            if x >= r[CX0] and (r[CX1] == 0 or x < r[CX1]) and not self.masked(y, x, x):
                yield x

    def pal_spans(self, y, w):
        """The spans of row y a PAL write reaches: any pixel in the rect, the clip, and out of the mask."""
        r = self.r
        last = min(r[DX] + w - 1, 255)
        for d in range(r[DX] >> 3, (last >> 3) + 1):
            x0 = d * 8
            if x0 + 7 >= r[CX0] and (r[CX1] == 0 or x0 < r[CX1]) and not self.masked(y, x0, x0 + 7):
                yield d

    def put(self, y, x, c):
        r = self.r
        self.pix[y][x] = self.pix[y][x] ^ c if r[FLAGS] & F_XOR else c

    def start(self, op):
        r = self.r
        w, h = self.geometry()
        if op == OP_FILL:
            for rr in range(h):
                y = r[DY] + rr
                if self.row_ok(y):
                    for x in self.xs(y):
                        self.put(y, x, r[FG] & 3)
        elif op == OP_PAL:
            for rr in range(h):
                y = r[DY] + rr
                if self.row_ok(y):
                    for d in self.pal_spans(y, w):
                        self.pal[y][d] = r[FG] & 3
        elif op == OP_COPY:
            order = range(h - 1, -1, -1) if r[DY] > r[SY] else range(h)
            for rr in order:
                ys = r[SY] + rr
                src = [self.pix[ys][x] if ys < SH else 0 for x in range(SW)] + [0] * 512
                spal = (self.pal[ys] if ys < SH else [0] * 32) + [0] * 64
                y = r[DY] + rr
                if self.row_ok(y):
                    for x in self.xs(y):
                        c = src[r[SX] + x - r[DX]]
                        if not (r[FLAGS] & F_KEY and c == r[KEY] & 3):
                            self.put(y, x, c)
                    if r[FLAGS] & F_PAL:
                        for d in self.pal_spans(y, w):
                            self.pal[y][d] = spal[(r[SX] + max(d * 8, r[DX]) - r[DX]) >> 3]
        else:
            # the rows use the registers as they were; the pen moves past the rect now
            self.stream = {"op": op, "row": 0, "bytes": [], "per": ((w + 7) >> 3) * (2 if op == OP_IMAGE else 1),
                           "r": dict(r)}
            r[DX] = (r[DX] + r[W]) & 0xFF

    def feed(self, d):
        s = self.stream
        s["bytes"].append(d)
        if len(s["bytes"]) < s["per"]:
            return
        live, self.r = self.r, s["r"]
        try:
            self.feed_row(s)
        finally:
            self.r = live
        s["bytes"] = []
        s["row"] += 1
        if s["row"] == self.geometry()[1]:
            self.stream = None

    def feed_row(self, s):
        r = self.r
        w, h = self.geometry()
        y = r[DY] + s["row"]
        b = s["bytes"]
        if self.row_ok(y):
            xs = set(self.xs(y))
            for k in range(w):
                x = r[DX] + k
                if x not in xs:
                    continue
                if s["op"] == OP_EXPAND:
                    bit = (b[k >> 3] >> (7 - (k & 7))) & 1
                    if not bit and r[FLAGS] & F_BG_CLEAR:
                        continue
                    c = r[FG] & 3 if bit else r[BG] & 3
                else:
                    p0 = (b[2 * (k >> 3)] >> (7 - (k & 7))) & 1
                    p1 = (b[2 * (k >> 3) + 1] >> (7 - (k & 7))) & 1
                    c = p1 << 1 | p0
                    if r[FLAGS] & F_KEY and c == r[KEY] & 3:
                        continue
                self.put(y, x, c)

    def frame(self):
        return [[self.pal[y][x >> 3] << 2 | self.pix[y][x] for x in range(SW)] for y in range(SH)]


def script(seed, n):
    """A random test: every op, clip, flag and the window, frames along the way."""
    rnd = random.Random(seed)
    out = []

    def wr(a, d):
        out.append(f"w {a:04x} {d & 0xff:02x}")

    def regs(**kv):
        for k, v in kv.items():
            wr(globals()[k.upper()], v)

    def op(o):
        out.append("p")
        wr(OP, o)

    regs(dx=0, dy=0, w=0, h=240, fg=0, flags=0, cx0=0, cy0=0, cx1=0, cy1=240)
    op(OP_FILL)
    op(OP_PAL)
    out.append("f")
    for i in range(n):
        kind = rnd.choice(["fill", "fill", "copy", "expand", "image", "pal", "win"])
        clip = rnd.random() < 0.3
        regs(cx0=rnd.randrange(0, 128) if clip else 0, cy0=rnd.randrange(0, 120) if clip else 0,
             cx1=rnd.randrange(128, 256) if clip else 0, cy1=rnd.randrange(120, 241) if clip else 240)
        if rnd.random() < 0.3:
            regs(mx0=rnd.randrange(0, 200), my0=rnd.randrange(0, 200), mx1=rnd.choice([0, rnd.randrange(64, 256)]),
                 my1=rnd.choice([0, rnd.randrange(64, 241)]))
        elif rnd.random() < 0.3:
            regs(mx0=0, mx1=0)
        flags = rnd.choice([0, 0, F_BG_CLEAR, F_KEY, F_XOR, F_KEY | F_XOR, F_BG_CLEAR | F_XOR])
        flags |= F_OVER if rnd.random() < 0.2 else 0
        regs(dx=rnd.randrange(256), dy=rnd.randrange(250), w=rnd.choice([rnd.randrange(1, 40), rnd.randrange(256)]),
             h=rnd.choice([rnd.randrange(1, 20), rnd.randrange(1, 120)]), fg=rnd.randrange(4), bg=rnd.randrange(4),
             key=rnd.randrange(4), flags=flags)
        if kind == "fill":
            op(OP_FILL)
        elif kind == "pal":
            op(OP_PAL)
        elif kind == "copy":
            regs(sx=rnd.randrange(256), sy=rnd.randrange(250))
            if rnd.random() < 0.5:
                regs(flags=flags | F_PAL)
            op(OP_COPY)
        elif kind in ("expand", "image"):
            w, h = rnd.randrange(1, 48), rnd.randrange(1, 12)
            regs(w=w, h=h)
            op(OP_EXPAND if kind == "expand" else OP_IMAGE)
            per = ((w + 7) >> 3) * (2 if kind == "image" else 1)
            for i in range(per * h):
                if i == 1 and rnd.random() < 0.3:  # the next rect's set up while this one streams in
                    regs(dx=rnd.randrange(256), dy=rnd.randrange(250), fg=rnd.randrange(4), flags=0)
                wr(DATA, rnd.randrange(256))
            if rnd.random() < 0.5:  # a second rect from the advanced pen, as text runs do
                op(OP_EXPAND if kind == "expand" else OP_IMAGE)
                for _ in range(per * h):
                    wr(DATA, rnd.randrange(256))
        else:
            out.append("p")
            wr(WIN_REG, rnd.randrange(12))
            for _ in range(rnd.randrange(1, 16)):
                a = WIN + rnd.randrange(0x800)
                wr(a, rnd.randrange(256))
                out.append(f"r {a:04x}")
        if rnd.random() < 0.08:
            out.append("p")
            out.append("f")
    out.append("p")
    out.append("f")
    return out


def run_model(lines):
    g, frames, reads = Gfx(), [], []
    for line in lines:
        w = line.split()
        if w[0] == "w":
            g.write(int(w[1], 16), int(w[2], 16))
        elif w[0] == "r":
            reads.append(f"{int(w[1], 16):04x} {g.read(int(w[1], 16)):02x}")
        elif w[0] == "f":
            frames.append(g.frame())
    return frames, reads


def save_png(frame, path):
    from PIL import Image
    gray = [(0, 0, 0), (85, 85, 85), (170, 170, 170), (255, 255, 255)]
    tint = [(1, 1, 1), (1, .6, .6), (.6, 1, .6), (.6, .6, 1)]
    im = Image.new("RGB", (SW, SH))
    im.putdata([tuple(int(g * t) for g, t in zip(gray[v & 3], tint[v >> 2])) for row in frame for v in row])
    im.save(path)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--sim', required=True, help="the tb_fb binary")
    ap.add_argument('--out', required=True, help="its working directory's out/")
    ap.add_argument('--seed', type=int, default=1)
    ap.add_argument('-n', type=int, default=300, help="random operations")
    a = ap.parse_args()
    out = Path(a.out)
    out.mkdir(exist_ok=True)
    for f in out.glob("frame*.txt"):
        f.unlink()
    lines = script(a.seed, a.n)
    (out / "script.txt").write_text("\n".join(lines) + "\n")
    frames, reads = run_model(lines)
    subprocess.run([str(Path(a.sim).resolve())], cwd=out.parent, check=True)
    bad = 0
    got_reads = (out / "reads.txt").read_text().split("\n")[:-1]
    for i, (want, got) in enumerate(zip(reads, got_reads)):
        if want != got:
            print(f"read {i}: model {want}, rtl {got}")
            bad += 1
    if len(got_reads) != len(reads):
        print(f"reads: model {len(reads)}, rtl {len(got_reads)}")
        bad += 1
    for i, want in enumerate(frames):
        path = out / f"frame{i}.txt"
        if not path.exists():
            print(f"frame {i}: missing")
            bad += 1
            continue
        got = [[int(c, 16) for c in row] for row in path.read_text().split()]
        diff = [(y, x) for y in range(SH) for x in range(SW) if got[y][x] != want[y][x]]
        save_png(got, out / f"frame{i}.png")
        if diff:
            save_png(want, out / f"frame{i}.want.png")
            y, x = diff[0]
            print(f"frame {i}: {len(diff)} pixels differ, first at {x},{y}: model {want[y][x]:x}, rtl {got[y][x]:x}")
            bad += 1
    print(f"gfxmodel: {len(frames)} frames, {len(reads)} reads, " + ("ok" if not bad else f"{bad} mismatches"))
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
