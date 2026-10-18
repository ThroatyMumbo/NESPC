"""icons/<name>_<size>.png (Windows 95 colors) as sprite records or IMAGE pictures, for mkchr.py."""
from pathlib import Path

from PIL import Image

from mkapptiles import spr_palette
from nesgfx import image_row, sprite_records

# letters of an IMAGE picture's colors in its palette (nes/include/desk.inc BG_PALETTE): the panels', the desk's
COLOR = {"K": 0, "G": 1, "W": 2, "D": 3, "T": 1, "Y": 3}
RGB = {"K": (0, 0, 0), "W": (255, 255, 255), "G": (192, 192, 192), "D": (128, 128, 128), "T": (0, 128, 128),
       "Y": (255, 255, 0)}
REGION = {"image": ("K", "G", "W", "D"), "desk": ("K", "T", "W", "Y")}  # colors 0-3; 1 where it is transparent

# <name>_<size>: how Desk shows it, its symbol (nes/include/desk.inc), and a grayed copy after it
ICONS = {
    "folder_32": ("desk", "IMG_FOLDER32", False),  # Files on the desktop, in the desk's palette
    "exe_32":("desk", "IMG_EXE32", False),  # a desktop shortcut to a program with no picture of its own
    "recycle_32": ("desk", "IMG_BIN32", False),  # the recycle bin, empty
    "recycle_full_32": ("desk", "IMG_BINFULL32", False),  # and with something in it
    "folder_16": ("sprite", "T_FOLDER16", False),  # the file window's title bar
    "exe_16": ("sprite", "T_EXE16", False),  # a program with no icon of its own
    "rom_16": ("sprite", "T_ROM16", False),  # a shortcut to a ROM, in the Start menu
    "back_16": ("image", "IMG_BACK", True),  # toolbar, on its gray
    "forward_16": ("image", "IMG_FWD", True),
    "up_16": ("image", "IMG_UP", True),
    "root_16": ("image", "IMG_ROOT", True),
}


def variant(stem):
    """("folder", 32) for folder_32, None for a name without a size."""
    name, _, size = stem.rpartition("_")
    return (name, int(size)) if name and size.isdigit() else None


def icon_image(icons, slot):
    """icons/<slot>.png, else the nearest size of the same icon scaled to fit."""
    name, size = variant(slot)
    exact = Path(icons) / f"{slot}.png"
    if exact.exists():
        return Image.open(exact).convert("RGBA")
    sizes = sorted((v[1] for p in Path(icons).glob(f"{name}_*.png") if (v := variant(p.stem)) and v[0] == name),
                   key=lambda s: (abs(s - size), -s))
    if not sizes:
        raise SystemExit(f"{icons}: no {name}_<size>.png for {slot}")
    im = Image.open(Path(icons) / f"{name}_{sizes[0]}.png").convert("RGBA")
    return im.resize((size, size), Image.Resampling.BOX if sizes[0] > size else Image.Resampling.NEAREST)


def check_size(im, slot, what):
    size = variant(slot)[1]
    if im.size != (size, size):
        raise SystemExit(f"{what}: {im.size[0]}x{im.size[1]}, {slot} is {size}x{size}")
    return size


def nearest_letter(rgb, region):
    return min(region, key=lambda k: sum((a - b) ** 2 for a, b in zip(rgb, RGB[k])))


def letters(im, region=REGION["image"], back="G"):
    """An RGBA picture as rows of the region's letters, transparent as back."""
    px = im.load()
    return [[back if px[c, r][3] < 128 else nearest_letter(px[c, r][:3], region) for c in range(im.width)]
            for r in range(im.height)]


def grayed(g, back="G"):
    """Windows' disabled look: the shape in dark gray over its white emboss one pixel down and right."""
    h, w = len(g), len(g[0])
    out = [[back] * w for _ in range(h)]
    for r in range(h):
        for c in range(w):
            if g[r][c] != back and r + 1 < h and c + 1 < w:
                out[r + 1][c + 1] = "W"
    for r in range(h):
        for c in range(w):
            if g[r][c] != back:
                out[r][c] = "D"
    return out


def image_bytes(g):
    """Letter rows as IMAGE data."""
    if len(g[0]) % 8:
        raise SystemExit(f"{len(g[0])} pixels a row: not whole spans")
    return b"".join(image_row([COLOR[ch] for ch in row]) for row in g)


def sprite_icon(im, slot, what, inc):
    check_size(im, slot, what)
    return sprite_records(im, spr_palette(inc))


def image_icon(im, slot, what):
    """The picture and, for a toolbar button, its grayed copy, as IMAGE data."""
    kind, _, gray = ICONS[slot]
    check_size(im, slot, what)
    region = REGION[kind]
    g = letters(im, region, region[1])
    return image_bytes(g) + (image_bytes(grayed(g)) if gray else b"")
