// The 32-bit word the NES reads off port 2 (elks/nes/src/keyboard/adapter.s): signature, tag | seq, two payload bytes;
// it goes out over D0, D3 and D4 together (kbdstream).
#ifndef KBDWORD_H
#define KBDWORD_H

#include <stdbool.h>
#include <stdint.h>

#define KBDWORD_BITS  32
#define KBDWORD_READS 11 // three lines, D0, D3 and D4, a $4017 read
#define KBDWORD_SIG   0x4B
#define KBDWORD_WHEEL 0x80 // a mouse wheel's notches, signed, positive toward the user (down the page)
#define KBDWORD_RAW   0x90 // raw mode (LINK_RAWKEYS): a HID usage going down or up
#define KBDWORD_KEY   0xA0 // tags, the high nibble of byte 1; a pad reads $F0 there, an empty port $00
#define KBDWORD_MOUSE 0xB0
#define KBDWORD_REPLY 0xC0 // a byte from the adapter's link
#define KBDWORD_MIDI  0xD0 // a MIDI keyboard's note on or off
#define KBDWORD_SYS   0xE0 // a system request to the running program, payload SYS_*
#define KBDWORD_D_MAX 63   // a mouse word's dx, dy are 7-bit signed

#define SYS_CLOSE 1 // Alt+F4: close the program
#define SYS_START 2 // a Windows key tapped alone: the Start menu
#define SYS_F12   3 // F12 alone: Desk's teaser

// key 0: no key, only a seq the NES has already seen
static inline uint32_t kbdword(uint8_t seq, uint8_t key) {
    return KBDWORD_SIG | (uint32_t)(KBDWORD_KEY | (seq & 15)) << 8 | (uint32_t)key << 16;
}

// usage 0xE0-0xE7: the modifiers, as their bits of a boot report
static inline uint32_t rawword(uint8_t seq, uint8_t usage, bool down) {
    return KBDWORD_SIG | (uint32_t)(KBDWORD_RAW | (seq & 15)) << 8 | (uint32_t)usage << 16 | (uint32_t)down << 24;
}

static inline uint32_t replyword(uint8_t seq, uint8_t b) {
    return KBDWORD_SIG | (uint32_t)(KBDWORD_REPLY | (seq & 15)) << 8 | (uint32_t)b << 16;
}

static inline uint32_t sysword(uint8_t seq, uint8_t code) {
    return KBDWORD_SIG | (uint32_t)(KBDWORD_SYS | (seq & 15)) << 8 | (uint32_t)code << 16;
}

static inline uint32_t wheelword(uint8_t seq, int notches) {
    return KBDWORD_SIG | (uint32_t)(KBDWORD_WHEEL | (seq & 15)) << 8 | (uint32_t)(notches & 0xff) << 16;
}

static inline uint32_t midiword(uint8_t seq, uint8_t note, bool on, uint8_t vel) {
    uint32_t n = (uint32_t)on << 7 | (note & 0x7f);
    return KBDWORD_SIG | (uint32_t)(KBDWORD_MIDI | (seq & 15)) << 8 | n << 16 | (uint32_t)(vel & 0x7f) << 24;
}

// the word as the PIO shifts it, 3 bits a read for D3, D4, D0: reads 0-7 put bytes 0, 1, 2 on D0, D3, D4 a bit each,
// LSB first; reads 8-10 put byte 3 on D0, D3, D4 in turn, the last read's D0 unused (adapter.s "receive")
static inline uint32_t kbdstream(uint32_t w) {
    static const uint8_t byte3[8] = {26, 24, 25, 29, 27, 28, 30, 31};
    uint32_t s = 0;
    for (int r = 0; r < 8; r++) {
        s |= (w >> (8 + r) & 1) << (3 * r);
        s |= (w >> (16 + r) & 1) << (3 * r + 1);
        s |= (w >> r & 1) << (3 * r + 2);
        s |= (w >> (24 + r) & 1) << byte3[r];
    }
    return s;
}

// buttons: bit 0 left, bit 1 right, as in a HID boot report; each rides in bit 7 above its delta
static inline uint32_t mouseword(uint8_t seq, int dx, int dy, uint8_t buttons) {
    uint32_t x = (uint32_t)(buttons & 1) << 7 | (uint32_t)(dx & 0x7f);
    uint32_t y = (uint32_t)(buttons >> 1 & 1) << 7 | (uint32_t)(dy & 0x7f);
    return KBDWORD_SIG | (uint32_t)(KBDWORD_MOUSE | (seq & 15)) << 8 | x << 16 | y << 24;
}

#endif
