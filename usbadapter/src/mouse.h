// A mouse's report-protocol layout from its HID report descriptor: buttons, relative X, Y and wheel.
#ifndef MOUSE_H
#define MOUSE_H

#include <stdbool.h>
#include <stdint.h>

#define MOUSE_BUTTONS 3

struct mouse_field {
    uint16_t bit;  // from the start of the report, past its ID byte
    uint8_t size;  // 0: the report has none
    bool sign;
};

struct mouse_layout {
    uint8_t id;    // the report the fields are in, 0 when the device uses no IDs
    bool ids;      // reports start with an ID byte
    struct mouse_field x, y, wheel, button[MOUSE_BUTTONS];
};

// false: no relative X and Y in it
bool mouse_parse(const uint8_t *desc, uint16_t len, struct mouse_layout *m);

// false: a report of another ID, or too short
bool mouse_read(const struct mouse_layout *m, const uint8_t *r, uint16_t len, int *dx, int *dy, int *wheel,
                uint8_t *buttons);

#endif
