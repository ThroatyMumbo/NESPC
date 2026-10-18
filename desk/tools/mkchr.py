#!/usr/bin/env python3
"""Desk's built-in pictures: the 4 KiB sprite table (cursor sheet, then the sprite icons at their nes/include/desk.inc
ids), the font as 8 1bpp rows a glyph from ' ', and the UI's IMAGE pictures (mkicons.py colors)."""
import argparse
from pathlib import Path

from PIL import Image

from deskinc import symbols
from mkicons import ICONS, grayed, icon_image, image_bytes, image_icon, sprite_icon
from nesgfx import encode

FONT_FIRST, FONT_LAST = 0x20, 0x7F


def grid(fill, w, h):
    return [[fill] * w for _ in range(h)]


def frame(g, r0, c0, r1, c1, color="K"):
    for r in range(r0, r1 + 1):
        g[r][c0] = g[r][c1] = color
    for c in range(c0, c1 + 1):
        g[r0][c] = g[r1][c] = color


def caption(kind, off=False):
    """A 16x14 caption button on the title bar: raised in white and black, whose navy leaves no room for dark gray."""
    g = grid("G", 16, 14)
    for c in range(16):
        g[0][c], g[13][c] = "W", "K"
    for r in range(14):
        g[r][0], g[r][15] = "W", "K"
    g[13][0] = "K"
    glyph = caption_glyph(kind)
    if off:
        glyph = grayed(glyph)  # its "D" is color 3: ui_captions gives these spans P_CHROME, else it's navy
    for r in range(1, 13):
        for c in range(1, 15):
            if glyph[r][c] != "G":
                g[r][c] = glyph[r][c]
    return g


def caption_glyph(kind):
    g = grid("G", 16, 14)
    if kind == "min":
        for r in (9, 10):
            for c in range(4, 10):
                g[r][c] = "K"
    elif kind == "zoom":
        frame(g, 2, 3, 10, 11)
        for c in range(3, 12):
            g[3][c] = "K"
    else:
        for i in range(7):
            for c in (4 + i, 5 + i, 10 - i, 11 - i):
                g[3 + i][c] = "K"
    return g


SB_UP = [(3, [3]), (4, [2, 3, 4])]
SB_DOWN = [(3, [2, 3, 4]), (4, [3])]


def sb_button(arrow=None, off=False):
    """An 8x8 scroll bar button: raised, its arrow black, or dark gray over white when it would do nothing."""
    g = grid("G", 8, 8)
    for i in range(8):
        g[0][i] = g[i][0] = "W"
    for i in range(1, 7):
        g[6][i] = g[i][6] = "D"
    for i in range(8):
        g[7][i] = g[i][7] = "K"
    for r, cs in arrow or []:
        for c in cs:
            if off:
                g[r + 1][c + 1] = "W"
    for r, cs in arrow or []:
        for c in cs:
            g[r][c] = "D" if off else "K"
    return g


SPRITE_COLORS = {(0, 0, 0): 1, (255, 255, 255): 2}


def cursor_tiles(path):
    im = Image.open(path)
    transparent = im.info.get('transparency')
    rgb = im.convert('RGB')
    px, ipx = rgb.load(), im.load()
    out = []
    for ty in range(im.height // 8):
        for tx in range(im.width // 8):
            out.append(["".join(
                "0" if ipx[tx * 8 + c, ty * 8 + r] == transparent else str(SPRITE_COLORS.get(px[tx * 8 + c, ty * 8 + r], 3))
                for c in range(8)) for r in range(8)])
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--font', required=True, help="nes86's terminal font CHR (background.chr)")
    ap.add_argument('--cursors', required=True, help="sheet of 8x8 cursors: transparent, black, white (assets/cursors.png)")
    ap.add_argument('--icons', required=True, help="directory of icon PNGs (icons/)")
    ap.add_argument('--inc', required=True, help="tile ids (nes/include/desk.inc)")
    ap.add_argument('--pals', required=True, help="directory for <slot>.pal, each sprite icon's tile palettes")
    ap.add_argument('--out-dir', required=True, help="directory for font.bin, tool.bin, desk.bin, caption.bin and sb.bin")
    ap.add_argument('-o', '--out', required=True, help="the sprite table")
    a = ap.parse_args()
    ids = {k: v for k, v in symbols(a.inc).items() if k.startswith("T_")}
    out = Path(a.out_dir)

    font = open(a.font, 'rb').read()
    (out / "font.bin").write_bytes(b"".join(font[c * 16 + 8:c * 16 + 16] for c in range(FONT_FIRST, FONT_LAST + 1)))
    for name, kind in (("tool.bin", "image"), ("desk.bin", "desk")):
        (out / name).write_bytes(b"".join(image_icon(icon_image(a.icons, s), s, f"{a.icons}/{s}.png")
                                          for s, (k, _, _) in ICONS.items() if k == kind))
    (out / "caption.bin").write_bytes(b"".join(image_bytes(caption(k)) for k in ("min", "zoom", "close")))
    (out / "caption_off.bin").write_bytes(b"".join(image_bytes(caption(k, off=True)) for k in ("zoom", "min")))
    (out / "sb.bin").write_bytes(b"".join(image_bytes(sb_button(*args)) for args in
                                          ((SB_UP,), (SB_DOWN,), (SB_UP, True), (SB_DOWN, True), ())))
    for p in sorted(Path(a.icons).glob("*.png")):
        if p.stem not in ICONS:
            print(f"{p}: Desk shows no {p.stem}, skipped")

    table = bytearray(0x1000)
    cursors = cursor_tiles(a.cursors)
    owner = {}
    for i, rows in enumerate(cursors):
        table[i * 16:(i + 1) * 16] = encode(rows)
        owner[i] = "cursors"
    for slot, (kind, sym, _) in ICONS.items():
        if kind != "sprite":
            continue
        recs = sprite_icon(icon_image(a.icons, slot), slot, f"{a.icons}/{slot}.png", a.inc)
        for i, rec in enumerate(recs, ids[sym]):
            if i > 0xFF or i in owner:
                raise SystemExit(f"{sym}: sprite tile ${i:02X} is {'taken by ' + owner[i] if i in owner else 'past $FF'}")
            owner[i] = sym
            table[i * 16:(i + 1) * 16] = rec[:16]
        open(Path(a.pals) / f"{slot}.pal", 'wb').write(bytes(rec[16] for rec in recs))
    for sym in ("T_MENU_ICON", "T_WIN_APP"):
        if ids[sym] in owner:
            raise SystemExit(f"{sym} ${ids[sym]:02X} is {owner[ids[sym]]}'s")
    open(a.out, 'wb').write(table)


if __name__ == '__main__':
    main()
