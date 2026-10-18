"""NES graphics for Desk's tools: the 2C02's colors, 2bpp tiles and IMAGE rows, the nearest colors and palettes,
sprite records, desktop pictures and their previews."""
from PIL import Image

# the 2C02 as emulators commonly show it; PNGs use these exact values, and black is the shared background color
NES_RGB = [
    0x7C7C7C, 0x0000FC, 0x0000BC, 0x4428BC, 0x940084, 0xA80020, 0xA81000, 0x881400,
    0x503000, 0x007800, 0x006800, 0x005800, 0x004058, 0x000000, 0x000000, 0x000000,
    0xBCBCBC, 0x0078F8, 0x0058F8, 0x6844FC, 0xD800CC, 0xE40058, 0xF83800, 0xE45C10,
    0xAC7C00, 0x00B800, 0x00A800, 0x00A844, 0x008888, 0x000000, 0x000000, 0x000000,
    0xF8F8F8, 0x3CBCFC, 0x6888FC, 0x9878F8, 0xF878F8, 0xF85898, 0xF87858, 0xFCA044,
    0xF8B800, 0xB8F818, 0x58D854, 0x58F898, 0x00E8D8, 0x787878, 0x000000, 0x000000,
    0xFCFCFC, 0xA4E4FC, 0xB8B8F8, 0xD8B8F8, 0xF8B8F8, 0xF8A4C0, 0xF0D0B0, 0xFCE0A8,
    0xF8D878, 0xD8F878, 0xB8F8B8, 0xB8F8D8, 0x00FCFC, 0xF8D8F8, 0x000000, 0x000000,
]


def rgb(color):
    v = NES_RGB[color]
    return v >> 16, v >> 8 & 0xFF, v & 0xFF


def encode(rows):
    """8 rows of 8 color digits as a 16-byte 2bpp tile: plane 0's rows, then plane 1's."""
    p0 = bytes(sum(((int(c) & 1) << (7 - i)) for i, c in enumerate(r)) for r in rows)
    p1 = bytes(sum(((int(c) >> 1) << (7 - i)) for i, c in enumerate(r)) for r in rows)
    return p0 + p1


def image_row(colors):
    """A row of 0-3 colors as IMAGE data: each 8 pixels' plane 0 byte, then its plane 1 byte."""
    out = bytearray()
    for x in range(0, len(colors), 8):
        v = colors[x:x + 8]
        out.append(sum((c & 1) << (7 - i) for i, c in enumerate(v)))
        out.append(sum((c >> 1) << (7 - i) for i, c in enumerate(v)))
    return bytes(out)


def nearest(c, colors, first=0):
    """> (squared error, index) of the RGB in colors nearest RGB c, numbered from first"""
    return min((sum((a - b) ** 2 for a, b in zip(c, k)), i) for i, k in enumerate(colors, first))


def fit_span(cells, bg, order=range(4)):
    """> (error, color indices, palette) of the background palette in order nearest a span's 8 pixels; a see-through
    pixel (alpha < 128) is color 1, so a span with one takes only a palette whose color 1 is the desk's"""
    clear = any(len(c) > 3 and c[3] < 128 for c in cells)
    best = None
    for p in order:
        if clear and bg[p * 4 + 1] != bg[1]:
            continue
        colors = [rgb(v) for v in bg[p * 4:p * 4 + 4]]
        err, idx = 0, []
        for c in cells:
            if len(c) > 3 and c[3] < 128:
                idx.append(1)
                continue
            d, i = nearest(c[:3], colors)
            err += d
            idx.append(i)
        if best is None or err < best[0]:
            best = (err, idx, p)
    return best


def sprite_records(im, spr_pal):
    """An RGBA icon to 17-byte records in reading order: pattern with color 0 transparent, then the sprite palette
    whose colors are nearest the tile's"""
    w, h = im.size
    if w % 8 or h % 8:
        raise SystemExit(f"{w}x{h}: not whole tiles")
    px = im.load()
    out = []
    for ty in range(0, h, 8):
        for tx in range(0, w, 8):
            cells = [[px[tx + c, ty + r] for c in range(8)] for r in range(8)]
            best = None
            for p in range(4):
                colors = [rgb(spr_pal[p * 4 + i]) for i in (1, 2, 3)]
                err, rows = 0, []
                for row in cells:
                    digits = ""
                    for c in row:
                        if c[3] < 128:
                            digits += "0"
                            continue
                        d, i = nearest(c[:3], colors, 1)
                        err += d
                        digits += str(i)
                    rows.append(digits)
                if best is None or err < best[0]:
                    best = (err, rows, p)
            out.append(encode(best[1]) + bytes([best[2]]))
    return out


def preview(records, w, spr_pal, scale=8):
    """Sprite records as the Desk shows them, scaled up, transparent pixels left clear."""
    im = Image.new("RGBA", (w, len(records) * 64 // w), (0, 0, 0, 0))
    px = im.load()
    for n, rec in enumerate(records):
        x0, y0 = n % (w // 8) * 8, n // (w // 8) * 8
        for r in range(8):
            for c in range(8):
                i = (rec[r] >> (7 - c) & 1) | (rec[8 + r] >> (7 - c) & 1) << 1
                if i:
                    px[x0 + c, y0 + r] = rgb(spr_pal[rec[16] * 4 + i]) + (255,)
    return im.resize((im.width * scale, im.height * scale), Image.Resampling.NEAREST)


def desk_picture(im, bg):
    """A 32x32 desktop picture in background palettes bg: its IMAGE data, then a byte a row of its four spans'
    palettes, span n in bits 2n-2n+1"""
    if im.size != (32, 32):
        raise SystemExit(f"{im.size[0]}x{im.size[1]}: a desktop picture is 32x32")
    px = im.load()
    rows, spans = bytearray(), bytearray()
    for y in range(32):
        row, sel = [], 0
        for s in range(4):
            # body and title last: on a tie, keep out of the window colors (Display)
            _, idx, p = fit_span([px[s * 8 + c, y] for c in range(8)], bg, (0, 3, 1, 2))
            row += idx
            sel |= p << (2 * s)
        rows += image_row(row)
        spans.append(sel)
    return bytes(rows + spans)


def picture_preview(data, bg):
    """desk_picture's bytes as Desk shows them on the desk."""
    im = Image.new("RGB", (32, 32))
    for y in range(32):
        sel = data[256 + y]
        for s in range(4):
            p0, p1 = data[y * 8 + s * 2], data[y * 8 + s * 2 + 1]
            for i in range(8):
                c = (p0 >> (7 - i) & 1) | (p1 >> (7 - i) & 1) << 1
                im.putpixel((s * 8 + i, y), rgb(bg[(sel >> (2 * s) & 3) * 4 + c]))
    return im
