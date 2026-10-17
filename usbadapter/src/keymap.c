#include "keymap.h"

#include <string.h>

#include "kbdword.h"

// usages 0x04-0x38: unshifted, shifted
static const char plain[][2] = {
    {'a', 'A'}, {'b', 'B'}, {'c', 'C'}, {'d', 'D'}, {'e', 'E'}, {'f', 'F'}, {'g', 'G'}, {'h', 'H'},
    {'i', 'I'}, {'j', 'J'}, {'k', 'K'}, {'l', 'L'}, {'m', 'M'}, {'n', 'N'}, {'o', 'O'}, {'p', 'P'},
    {'q', 'Q'}, {'r', 'R'}, {'s', 'S'}, {'t', 'T'}, {'u', 'U'}, {'v', 'V'}, {'w', 'W'}, {'x', 'X'},
    {'y', 'Y'}, {'z', 'Z'}, {'1', '!'}, {'2', '@'}, {'3', '#'}, {'4', '$'}, {'5', '%'}, {'6', '^'},
    {'7', '&'}, {'8', '*'}, {'9', '('}, {'0', ')'}, {'\r', '\r'}, {0x1b, 0x1b}, {0x08, 0x08}, {'\t', '\t'},
    {' ', ' '}, {'-', '_'}, {'=', '+'}, {'[', '{'}, {']', '}'}, {'\\', '|'}, {'#', '~'}, {';', ':'},
    {'\'', '"'}, {'`', '~'}, {',', '<'}, {'.', '>'}, {'/', '?'},
};
static const char keypad[] = "/*-+\r1234567890.";

// usages 0x49-0x52: Insert, Home, Page Up, Delete, End, Page Down, Right, Left, Down, Up
static const char *const vt[] = {
    "\033[2~", "\033[H", "\033[5~", "\033[3~", "\033[F", "\033[6~", "\033[C", "\033[D", "\033[B", "\033[A",
};

// keypad 1-9, 0, . with num lock off, as usages 0x49-0x52; 0 is keypad 5, which sends nothing
static const uint8_t keypad_nav[] = {0x4d, 0x51, 0x4e, 0x50, 0, 0x4f, 0x4a, 0x52, 0x4b, 0x49, 0x4c};

int keymap(uint8_t key, uint8_t mods, uint8_t locks, uint8_t out[KEYMAP_MAX]) {
    int n = 0;
    // shift flips num lock for the keypad's digits, as on a PC
    if (key >= 0x59 && key <= 0x63 && !(locks & LOCK_NUM) == !(mods & MOD_SHIFT))
        key = keypad_nav[key - 0x59];
    if ((key >= 0x49 && key <= 0x52) || key == KEYMAP_F2) {
        const char *s = key == KEYMAP_F2 ? "\033OQ" : vt[key - 0x49];
        if (key == 0x4c && (mods & MOD_SHIFT))
            s = "\033[3;2~"; // xterm's Shift+Delete: Desk deletes for good, past the Trash
        n = (int)strlen(s);
        memcpy(out, s, (size_t)n);
        return n;
    }
    char c;
    if (key >= 0x04 && key <= 0x38) {
        bool shift = mods & MOD_SHIFT;
        if (key <= 0x1d && (locks & LOCK_CAPS))
            shift = !shift;
        c = plain[key - 0x04][shift];
    } else if (key >= 0x54 && key <= 0x63) {
        c = keypad[key - 0x54];
    } else {
        return 0;
    }
    if (mods & MOD_CTRL) {
        if (c >= 'a' && c <= 'z')
            c = (char)(c - 'a' + 1);
        else if (c >= '[' && c <= '_')
            c = (char)(c - '@');
        else if (c >= 'A' && c <= 'Z')
            c = (char)(c - 'A' + 1);
    }
    if (mods & MOD_ALT)
        out[n++] = 0x1b;
    out[n++] = (uint8_t)c;
    return n;
}

uint8_t keymap_sys(uint8_t key, uint8_t mods) {
    if (key == KEYMAP_F12 && !mods)
        return SYS_F12;
    return key == KEYMAP_F4 && (mods & MOD_ALT) ? SYS_CLOSE : 0;
}

uint8_t keymap_tap(bool *armed, uint8_t mods, uint8_t prev, const uint8_t keys[6]) {
    bool other = mods & ~MOD_GUI;
    for (int i = 0; i < 6; i++)
        other |= keys[i] != 0;
    if (other) {
        *armed = false;
        return 0;
    }
    if (mods) {
        if (!(prev & MOD_GUI))
            *armed = true;
        return 0;
    }
    bool tap = *armed;
    *armed = false;
    return tap ? SYS_START : 0;
}
