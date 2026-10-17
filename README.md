# (WIP) NESPC Desktop Environment

A retro desktop environment for the NES.

Demo video: https://youtu.be/o0s7tRcqsOs

This repo is WIP as I cleanup and push each piece of this project in a public-ready state. Apologies for my inevitable tardiness.

## Contents
- `usbadapter/`: The USB adapter firmware for attaching a keyboard, mouse or even MIDI keyboard to your NES. Requires an RP2350-based MCU and NES controller cable.
- `nes/`: The NES side of the adapter: the 6502 driver (`nes/src/keyboard/adapter.s`) and an (untested) PS/2 keyboard driver (`ps2.s`).
- `tests/`: Test ROMs for the adapter: `kbdtest` (raw keyboard input), `linktest` (link echo) and `speedtest` (transfer rates).
- `edn8.py`: Loads a ROM (and optionally an FPGA core) onto an EverDrive N8 Pro over USB

## Credits
- [nes86](https://github.com/decrazyo/nes86) (GPLv3): the 8x8 font (`nes/data/background.chr`) and the keyboard framework (`nes/include/const.inc`, `keyboard.inc`).
- [krikzz/EDN8-PRO](https://github.com/krikzz/EDN8-PRO): the EverDrive N8 Pro base FPGA sources. They are fetched at build time and are not included here.
