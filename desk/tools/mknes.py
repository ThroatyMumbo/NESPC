#!/usr/bin/env python3
"""Wrap a PRG in 16 KiB banks as NES 2.0 mapper 773, or --mapper's, with 8 KiB PRG and CHR RAM."""
import argparse

PRG_MIN, PRG_BANK, CHR_BANK = 0x8000, 0x4000, 0x2000
PRG_MAX = 0x7E0000  # the OS lives above it in PRG PSRAM
BANKS_MAX = 0xEFF   # a size nibble of $F is NES 2.0's exponent form, which src/launch.s rejects
SHELL_BANK = 2  # nes/include/desk.inc: the PSRAM bank past the 32 KiB at $8000-$FFFF
MAPPER = 773
CHR_RAM_SHIFT = 7  # 64 << 7 = 8 KiB
PRG_RAM_SHIFT = 7  # $6000-$7FFF; without it the base masks SRAM off
RSRC_BLOCK = 1024  # what rom_rsrc reads


def prg_banks(prg):
    """{bank: its 16 KiB} for the PRG past the first 32 KiB, as $5010 maps them at $8000"""
    return {SHELL_BANK + i: list(prg[o:o + PRG_BANK]) for i, o in enumerate(range(PRG_MIN, len(prg), PRG_BANK))}


def header(prg_size, mapper=MAPPER, misc=0, chr_size=0, nvram=0):
    prg_n, chr_n = prg_size // PRG_BANK, chr_size // CHR_BANK
    h = bytearray(16)
    h[0:4] = b"NES\x1a"
    h[4] = prg_n & 0xFF
    h[5] = chr_n & 0xFF
    h[6] = (mapper & 0x0F) << 4 | (0x02 if nvram else 0)
    h[7] = (mapper & 0xF0) | 0x08
    h[8] = (mapper >> 8) & 0x0F
    h[9] = (prg_n >> 8) | (chr_n >> 8) << 4
    h[10] = PRG_RAM_SHIFT | (nvram.bit_length() - 7) << 4 if nvram else PRG_RAM_SHIFT
    h[11] = 0 if chr_size else CHR_RAM_SHIFT
    h[14] = misc
    return bytes(h)


def rom(prg, mapper=MAPPER, rsrc=b"", chr_rom=b"", prg_max=PRG_MAX, nvram=0):
    """the .nes: header, PRG, CHR, then the resource section rsrc, if any, padded to RSRC_BLOCK"""
    if len(prg) < PRG_MIN or len(prg) % PRG_BANK or len(prg) // PRG_BANK > BANKS_MAX:
        raise SystemExit(f"want 32 KiB or more of PRG in 16 KiB banks, got {len(prg)} B")
    if len(prg) > prg_max:
        raise SystemExit(f"PRG is {len(prg):#x} B, past {prg_max:#x}")
    if len(chr_rom) % CHR_BANK or len(chr_rom) // CHR_BANK > BANKS_MAX:
        raise SystemExit(f"want CHR in 8 KiB banks, got {len(chr_rom)} B")
    if nvram and (nvram & (nvram - 1) or not 0x2000 <= nvram <= 0x40000):
        raise SystemExit(f"want NVRAM a power of two from 8 KiB to 256 KiB, got {nvram} B")
    return (header(len(prg), mapper, 1 if rsrc else 0, len(chr_rom), nvram) + prg + chr_rom +
            rsrc.ljust(RSRC_BLOCK if rsrc else 0, b"\0"))


def pad(data, block):
    return data + bytes(-len(data) % block)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("prg")
    ap.add_argument("-o", "--out", required=True)
    ap.add_argument("--mapper", type=int, default=MAPPER)
    ap.add_argument("--append", action="append", default=[], help="a file to add to the PRG, padded to 16 KiB")
    ap.add_argument("--chr", help="the CHR ROM, padded to 8 KiB")
    ap.add_argument("--prg-max", type=lambda s: int(s, 0), default=PRG_MAX, help="fail past this many PRG bytes")
    ap.add_argument("--nvram", type=lambda s: int(s, 0), default=0,
                    help="battery-backed SRM of this many bytes, which Desk saves to the SD")
    a = ap.parse_args()
    prg = open(a.prg, "rb").read()
    for p in a.append:
        prg += pad(open(p, "rb").read(), PRG_BANK)
    chr_rom = pad(open(a.chr, "rb").read(), CHR_BANK) if a.chr else b""
    with open(a.out, "wb") as f:
        f.write(rom(prg, a.mapper, b"", chr_rom, a.prg_max, a.nvram))


if __name__ == "__main__":
    main()
