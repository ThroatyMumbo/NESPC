#include <stdio.h>
#include <string.h>

#include "kbdword.h"
#include "keymap.h"

static int fails;

static void expect(const char *name, uint8_t key, uint8_t mods, uint8_t locks, const char *want) {
    uint8_t out[KEYMAP_MAX];
    int n = keymap(key, mods, locks, out);
    if (n != (int)strlen(want) || memcmp(out, want, (size_t)n)) {
        printf("FAIL %s: got %d bytes", name, n);
        for (int i = 0; i < n; i++)
            printf(" %02x", out[i]);
        printf("\n");
        fails++;
    }
}

static void expect_sys(const char *name, uint8_t key, uint8_t mods, uint8_t want) {
    if (keymap_sys(key, mods) != want) {
        printf("FAIL %s: sys %u, want %u\n", name, keymap_sys(key, mods), want);
        fails++;
    }
}

// reports as modifier, key pairs; want: the SYS_* the last one makes
static void expect_tap(const char *name, int n, const uint8_t (*reps)[2], uint8_t want) {
    bool armed = false;
    uint8_t prev = 0, got = 0;
    for (int i = 0; i < n; i++) {
        uint8_t keys[6] = {reps[i][1]};
        got = keymap_tap(&armed, reps[i][0], prev, keys);
        prev = reps[i][0];
    }
    if (got != want) {
        printf("FAIL %s: tap %u, want %u\n", name, got, want);
        fails++;
    }
}

static void expect_word(uint8_t seq, uint8_t key, uint32_t want) {
    if (kbdword(seq, key) != want) {
        printf("FAIL word(%u, %02x) = %06lx, want %06lx\n", seq, key, (unsigned long)kbdword(seq, key),
               (unsigned long)want);
        fails++;
    }
}

static void expect_mouse(uint8_t seq, int dx, int dy, uint8_t buttons, uint32_t want) {
    if (mouseword(seq, dx, dy, buttons) != want) {
        printf("FAIL mouse(%u, %d, %d, %u) = %08lx, want %08lx\n", seq, dx, dy, buttons,
               (unsigned long)mouseword(seq, dx, dy, buttons), (unsigned long)want);
        fails++;
    }
}

static void expect_midi(uint8_t seq, uint8_t note, bool on, uint8_t vel, uint32_t want) {
    if (midiword(seq, note, on, vel) != want) {
        printf("FAIL midi(%u, %u, %d, %u) = %08lx, want %08lx\n", seq, note, on, vel,
               (unsigned long)midiword(seq, note, on, vel), (unsigned long)want);
        fails++;
    }
}

// the word back from a stream, as adapter.s "receive" rotates the lines in
static uint32_t nes_reads(uint32_t s) {
    uint8_t b[4] = {0};
    int k = 0;
    for (int r = 0; r < KBDWORD_READS; r++) {
        uint64_t g = (uint64_t)s >> (3 * r) & 7; // read 10's D0 is past the 32 bits: 0
        uint8_t d3 = g & 1, d4 = g >> 1 & 1, d0 = g >> 2 & 1;
        if (r < 8) {
            b[0] |= d0 << r;
            b[1] |= d3 << r;
            b[2] |= d4 << r;
        } else {
            if (r < 10)
                b[3] |= d0 << k++;
            b[3] |= d3 << k++;
            b[3] |= d4 << k++;
        }
    }
    return b[0] | (uint32_t)b[1] << 8 | (uint32_t)b[2] << 16 | (uint32_t)b[3] << 24;
}

static void expect_stream(uint32_t w) {
    uint32_t s = kbdstream(w), back = nes_reads(s);
    if (back != w) {
        printf("FAIL stream(%08lx) = %08lx, reads back %08lx\n", (unsigned long)w, (unsigned long)s,
               (unsigned long)back);
        fails++;
    }
    // port.c tells a finished word from an upstream byte by the byte's 1s in bits 0-23
    if ((w & 0xff) == KBDWORD_SIG && (s & 0xffffff) == 0xffffff) {
        printf("FAIL stream(%08lx) = %08lx looks like an upstream byte\n", (unsigned long)w, (unsigned long)s);
        fails++;
    }
}

int main(void) {
    expect("a", 0x04, 0, 0, "a");
    expect("shift a", 0x04, 0x02, 0, "A");
    expect("right shift a", 0x04, 0x20, 0, "A");
    expect("caps a", 0x04, 0, LOCK_CAPS, "A");
    expect("caps shift a", 0x04, 0x02, LOCK_CAPS, "a");
    expect("caps 1", 0x1e, 0, LOCK_CAPS, "1");
    expect("num lock a", 0x04, 0, LOCK_NUM | LOCK_SCROLL, "a");
    expect("shift 2", 0x1f, 0x02, 0, "@");
    expect("enter", 0x28, 0, 0, "\r");
    expect("keypad enter", 0x58, 0, 0, "\r");
    expect("backspace", 0x2a, 0, 0, "\b");
    expect("esc", 0x29, 0, 0, "\033");
    expect("ctrl c", 0x06, 0x01, 0, "\003");
    expect("right ctrl c", 0x06, 0x10, 0, "\003");
    expect("ctrl shift c", 0x06, 0x03, 0, "\003");
    expect("ctrl [", 0x2f, 0x01, 0, "\033");
    expect("alt x", 0x1b, 0x04, 0, "\033x");
    expect("up", 0x52, 0, 0, "\033[A");
    expect("left", 0x50, 0, 0, "\033[D");
    expect("delete", 0x4c, 0, 0, "\033[3~");
    expect("shift delete", 0x4c, 0x02, 0, "\033[3;2~");
    expect("right shift delete", 0x4c, 0x20, 0, "\033[3;2~");
    expect("slash", 0x38, 0, 0, "/");
    expect("question", 0x38, 0x02, 0, "?");
    expect("keypad 7", 0x5f, 0, LOCK_NUM, "7");
    expect("keypad .", 0x63, 0, LOCK_NUM, ".");
    expect("keypad 7 no num", 0x5f, 0, 0, "\033[H");
    expect("keypad 8 no num", 0x60, 0, 0, "\033[A");
    expect("keypad 3 no num", 0x5b, 0, 0, "\033[6~");
    expect("keypad 0 no num", 0x62, 0, 0, "\033[2~");
    expect("keypad . no num", 0x63, 0, 0, "\033[3~");
    expect("keypad 5 no num", 0x5d, 0, 0, "");
    expect("shift keypad 4", 0x5c, 0x02, LOCK_NUM, "\033[D");
    expect("shift keypad 4 no num", 0x5c, 0x02, 0, "4");
    expect("keypad / no num", 0x54, 0, 0, "/");
    expect("keypad enter no num", 0x58, 0, 0, "\r");
    expect("caps lock", 0x39, 0, 0, "");
    expect("num lock", 0x53, 0, 0, "");
    expect("scroll lock", 0x47, 0, 0, "");
    expect("f1", 0x3a, 0, 0, "");
    expect("f2", 0x3b, 0, 0, "\033OQ");
    expect_sys("alt f4", 0x3d, 0x04, SYS_CLOSE);
    expect_sys("right alt f4", 0x3d, 0x40, SYS_CLOSE);
    expect_sys("f4", 0x3d, 0, 0);
    expect_sys("ctrl f4", 0x3d, 0x01, 0);
    expect_sys("alt f3", 0x3c, 0x04, 0);
    expect_sys("alt a", 0x04, 0x04, 0);
    expect_sys("f12", 0x45, 0, SYS_F12);
    expect_sys("shift f12", 0x45, 0x02, 0);
    expect_tap("win tap", 2, (const uint8_t[][2]){{0x08, 0}, {0, 0}}, SYS_START);
    expect_tap("right win tap", 2, (const uint8_t[][2]){{0x80, 0}, {0, 0}}, SYS_START);
    expect_tap("win down", 1, (const uint8_t[][2]){{0x08, 0}}, 0);
    expect_tap("win held, repeat report", 3, (const uint8_t[][2]){{0x08, 0}, {0x08, 0}, {0, 0}}, SYS_START);
    expect_tap("win e", 4, (const uint8_t[][2]){{0x08, 0}, {0x08, 0x08}, {0x08, 0}, {0, 0}}, 0);
    expect_tap("win shift", 4, (const uint8_t[][2]){{0x08, 0}, {0x0a, 0}, {0x08, 0}, {0, 0}}, 0);
    expect_tap("ctrl win", 4, (const uint8_t[][2]){{0x01, 0}, {0x09, 0}, {0x08, 0}, {0, 0}}, 0);
    expect_tap("win, again", 4, (const uint8_t[][2]){{0x08, 0}, {0, 0}, {0x08, 0}, {0, 0}}, SYS_START);
    expect_tap("key alone", 2, (const uint8_t[][2]){{0, 0x04}, {0, 0}}, 0);

    expect_word(0, 0, 0x00a04b);
    expect_word(1, 'l', 0x6ca14b);
    expect_word(17, 's', 0x73a14b);
    expect_mouse(2, 0, 0, 0, 0x0000b24b);
    expect_mouse(3, 5, -1, 0, 0x7f05b34b);
    expect_mouse(4, -63, 63, 1, 0x3fc1b44b);
    expect_mouse(5, 0, 0, 2, 0x8000b54b);
    expect_mouse(21, 1, 1, 7, 0x8181b54b);
    expect_midi(6, 60, true, 100, 0x64bcd64b);
    expect_midi(7, 60, false, 0, 0x003cd74b);
    expect_midi(24, 127, true, 127, 0x7fffd84b);
    expect_midi(9, 0x80, true, 0xff, 0x7f80d94b);
    expect_stream(0);
    expect_stream(0xffffffff);
    expect_stream(kbdword(3, 'x'));
    expect_stream(mouseword(5, -63, 63, 3));
    expect_stream(midiword(9, 127, true, 127));
    expect_stream(sysword(10, SYS_CLOSE));
    if (sysword(10, SYS_CLOSE) != 0x01ea4b) {
        printf("FAIL sysword = %06lx\n", (unsigned long)sysword(10, SYS_CLOSE));
        fails++;
    }
    for (uint32_t w = 1; w; w <<= 1)
        expect_stream(w | KBDWORD_SIG);

    printf(fails ? "%d failed\n" : "ok\n", fails);
    return fails != 0;
}
