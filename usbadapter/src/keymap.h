// HID boot-keyboard usages to terminal bytes: US layout, Ctrl+letter 1-26, Alt as an ESC prefix, VT keys.
#ifndef KEYMAP_H
#define KEYMAP_H

#include <stdbool.h>
#include <stdint.h>

#define KEYMAP_MAX 6 // Shift+Delete's ESC [3;2~

// lock key usages
#define KEYMAP_NUMLOCK 0x53
#define KEYMAP_CAPS    0x39
#define KEYMAP_SCROLL  0x47
#define KEYMAP_F2      0x3b // VT100's PF2, ESC O Q: Desk's rename
#define KEYMAP_F4      0x3d
#define KEYMAP_F12     0x45

// boot report modifier bits, left and right together
#define MOD_CTRL  0x11
#define MOD_SHIFT 0x22
#define MOD_ALT   0x44
#define MOD_GUI   0x88

// lock state bits, laid out like the HID LED output report
#define LOCK_NUM    0x01
#define LOCK_CAPS   0x02
#define LOCK_SCROLL 0x04

// bytes for usage `key` under the boot report's modifier byte `mods` into out; returns how many, 0 for none
int keymap(uint8_t key, uint8_t mods, uint8_t locks, uint8_t out[KEYMAP_MAX]);

// the SYS_* request (kbdword.h) usage `key` under `mods` makes instead of bytes, 0 for none
uint8_t keymap_sys(uint8_t key, uint8_t mods);

// SYS_START when a report releases a Windows key that went down and up with nothing else; `armed` carries over
uint8_t keymap_tap(bool *armed, uint8_t mods, uint8_t prev, const uint8_t keys[6]);

#endif
