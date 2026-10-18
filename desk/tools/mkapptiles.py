#!/usr/bin/env python3
"""A Desk program's PNG strips to K_CHR records, its <name>_32.png to a desktop picture (.pic), and its palette file
("entry color" in hex, or a window color's name) to palette.bin's K_PAL pairs."""
import argparse
from pathlib import Path

from PIL import Image

from deskinc import define, symbols
from nesgfx import NES_RGB, desk_picture, encode, nearest, picture_preview, rgb  # noqa: F401 (the SDK's tools)

BLACK = (0, 0, 0)
ORDER = (1, 3, 0, 2)  # the body's palette, the program's own, first
SCHEME = ("face", "shadow", "title")  # K_COLORS's slots, SC_* order
PAL_SCHEME = 0x40  # apps/include/desk.inc


def spr_palette(inc):
    """The sprite palettes icons are drawn in, from nes/include/taskbar.inc through desk.inc."""
    return define(inc, "SPR_PALETTE")


def desk_palette(inc):
    """The Desk's background palettes and the entries a program may change, from nes/include/desk.inc."""
    pal = define(inc, "BG_PALETTE")
    allowed = symbols(inc)["APP_COLORS"]
    return pal, allowed


def program_palette(path, pal, allowed, scheme):
    pairs = []
    for n, line in enumerate(open(path), 1):
        words = line.split("#")[0].split()
        if not words:
            continue
        entry = int(words[0], 16)
        if entry > 15 or not allowed >> entry & 1:
            raise SystemExit(f"{path}:{n}: entry {entry:X} is the Desk's (APP_COLORS)")
        if words[1] in SCHEME:
            slot = SCHEME.index(words[1])
            pal[entry] = scheme[slot]
            pairs.append((entry, PAL_SCHEME + slot))
        else:
            pal[entry] = int(words[1], 16)
            pairs.append((entry, pal[entry]))
    return pairs


def tile_records(png, pal):
    """Each tile in the palette that holds its colors, else the one nearest them, saying what changed."""
    im = Image.open(png).convert("RGB")
    w, h = im.size
    if h % 8 or w % h:
        raise SystemExit(f"{png}: {w}x{h}, want a strip of square pictures a multiple of 8 high")
    px = im.load()
    out = bytearray()
    for x0 in range(0, w, h):
        for ty in range(0, h, 8):
            for tx in range(x0, x0 + h, 8):
                cells = [[px[tx + c, ty + r] for c in range(8)] for r in range(8)]
                colors = sorted({p for row in cells for p in row} - {BLACK})
                at = {p: [rgb(v) for v in pal[p * 4 + 1:p * 4 + 4]] for p in ORDER}
                err, p = min((sum(nearest(c, at[p], 1)[0] for c in colors), p) for p in ORDER)
                index = {c: nearest(c, at[p], 1)[1] for c in colors}
                if err:
                    moved = ", ".join(f"{c} as {rgb(pal[p * 4 + i])}" for c, i in index.items() if rgb(pal[p * 4 + i]) != c)
                    print(f"{png}: tile at {tx},{ty} in palette {p}: {moved}")
                rows = ["".join("0" if c == BLACK else str(index[c]) for c in row) for row in cells]
                out += encode(rows) + bytes([p])
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('png', nargs='*')
    ap.add_argument('--inc', required=True, help="the Desk's palettes (nes/include/desk.inc)")
    ap.add_argument('--palette', help="the program's palette entries")
    ap.add_argument('-o', '--out', required=True, help="directory for <png>.chr and palette.bin")
    a = ap.parse_args()
    pal, allowed = desk_palette(a.inc)
    scheme = define(Path(a.inc).parent / "colors.inc", "SC_DEFAULT")
    pairs = program_palette(a.palette, pal, allowed, scheme) if a.palette else []
    out = Path(a.out)
    for png in a.png:
        if Path(png).stem.endswith("_32"):
            pic = desk_picture(Image.open(png).convert("RGBA"), pal)
            (out / f"{Path(png).stem}.pic").write_bytes(pic)
            picture_preview(pic, pal).save(out / f"{Path(png).stem}.desk.png")
            continue
        (out / f"{Path(png).stem}.chr").write_bytes(tile_records(png, pal))
    (out / "palette.bin").write_bytes(bytes(b for pair in pairs for b in pair) + b"\xff")


if __name__ == '__main__':
    main()
