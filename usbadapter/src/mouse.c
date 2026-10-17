// HID 1.11 section 6.2.2: short items only, as mice use; Push and Pop are not followed.
#include <string.h>

#include "mouse.h"

#define PAGE_DESKTOP   0x01
#define PAGE_BUTTON    0x09
#define USAGE_X        0x30
#define USAGE_Y        0x31
#define USAGE_WHEEL    0x38
#define MAIN_CONST     0x01 // Input item flags
#define MAIN_VARIABLE  0x02
#define MAIN_RELATIVE  0x04
#define USAGES_MAX     16
#define IDS_MAX        16
#define FIND           (-1)

struct offsets {
    uint8_t n;
    uint8_t id[IDS_MAX];
    uint16_t bits[IDS_MAX];
};

static uint16_t *offset_of(struct offsets *o, uint8_t id) {
    for (int i = 0; i < o->n; i++)
        if (o->id[i] == id)
            return &o->bits[i];
    if (o->n == IDS_MAX)
        return NULL;
    o->id[o->n] = id;
    o->bits[o->n] = 0;
    return &o->bits[o->n++];
}

// want FIND: the ID of the first relative X; else the fields of report `want` into m
static int walk(const uint8_t *d, uint16_t len, int want, struct mouse_layout *m) {
    struct offsets o = {0};
    uint32_t page = 0, size = 0, count = 0, usages[USAGES_MAX], umin = 0, umax = 0, nu = 0;
    int32_t lmin = 0;
    uint8_t id = 0;
    bool range = false;
    for (uint16_t i = 0; i < len;) {
        uint8_t p = d[i++];
        if (p == 0xFE) { // long item: size, tag, data
            if (i >= len)
                break;
            i += 2 + d[i];
            continue;
        }
        uint8_t n = p & 3;
        if (n == 3)
            n = 4;
        if (i + n > len)
            break;
        uint32_t v = 0;
        for (int k = 0; k < n; k++)
            v |= (uint32_t)d[i + k] << 8 * k;
        int32_t sv = n == 1 ? (int8_t)v : n == 2 ? (int16_t)v : (int32_t)v;
        i += n;
        uint8_t type = p >> 2 & 3, tag = p >> 4;
        uint32_t usage = n == 4 ? v : page << 16 | v;
        if (type == 1) {
            if (tag == 0)
                page = v;
            else if (tag == 1)
                lmin = sv;
            else if (tag == 7)
                size = v;
            else if (tag == 8) {
                id = (uint8_t)v;
                m->ids = true;
            } else if (tag == 9)
                count = v;
            continue;
        }
        if (type == 2) {
            if (tag == 0 && nu < USAGES_MAX)
                usages[nu++] = usage;
            else if (tag == 1) {
                umin = usage;
                range = true;
            } else if (tag == 2)
                umax = usage;
            continue;
        }
        if (type != 0)
            continue;
        if (tag == 8) {
            uint16_t *at = offset_of(&o, id);
            if (!at)
                break;
            bool live = (v & (MAIN_CONST | MAIN_VARIABLE)) == MAIN_VARIABLE && size && size <= 32;
            for (uint32_t k = 0; k < count; k++, *at += size) {
                if (!live)
                    continue;
                uint32_t u = range ? (umin + k < umax ? umin + k : umax) : nu ? usages[k < nu ? k : nu - 1] : 0;
                struct mouse_field f = {*at, (uint8_t)size, lmin < 0};
                if (u == (PAGE_DESKTOP << 16 | USAGE_X) && v & MAIN_RELATIVE) {
                    if (want == FIND)
                        return id;
                    if (id == want)
                        m->x = f;
                }
                if (id != want)
                    continue;
                if (u == (PAGE_DESKTOP << 16 | USAGE_Y) && v & MAIN_RELATIVE)
                    m->y = f;
                else if (u == (PAGE_DESKTOP << 16 | USAGE_WHEEL) && v & MAIN_RELATIVE)
                    m->wheel = f;
                else if (u > PAGE_BUTTON << 16 && u <= (PAGE_BUTTON << 16 | MOUSE_BUTTONS))
                    m->button[(u & 0xffff) - 1] = f;
            }
        }
        nu = 0;
        range = false;
        umin = umax = 0;
    }
    return FIND;
}

bool mouse_parse(const uint8_t *desc, uint16_t len, struct mouse_layout *m) {
    memset(m, 0, sizeof *m);
    int id = walk(desc, len, FIND, m);
    if (id == FIND)
        return false;
    m->id = (uint8_t)id;
    walk(desc, len, id, m);
    return m->x.size && m->y.size;
}

// 0 for a field past the end of the report
static int32_t field(const struct mouse_field *f, const uint8_t *r, uint16_t len) {
    if (!f->size || f->bit + f->size > len * 8u)
        return 0;
    uint32_t v = 0;
    for (int k = 0; k < f->size; k++) {
        unsigned b = f->bit + k;
        v |= (uint32_t)(r[b >> 3] >> (b & 7) & 1) << k;
    }
    if (f->sign && f->size < 32 && v >> (f->size - 1) & 1)
        v |= ~0u << f->size;
    return (int32_t)v;
}

bool mouse_read(const struct mouse_layout *m, const uint8_t *r, uint16_t len, int *dx, int *dy, int *wheel,
                uint8_t *buttons) {
    if (m->ids) {
        if (!len || r[0] != m->id)
            return false;
        r++;
        len--;
    }
    if (m->y.bit + m->y.size > len * 8u || m->x.bit + m->x.size > len * 8u)
        return false;
    *dx = field(&m->x, r, len);
    *dy = field(&m->y, r, len);
    *wheel = field(&m->wheel, r, len);
    *buttons = 0;
    for (int b = 0; b < MOUSE_BUTTONS; b++)
        if (field(&m->button[b], r, len))
            *buttons |= 1 << b;
    return true;
}
