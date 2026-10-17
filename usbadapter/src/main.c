// USB keyboard, mouse and MIDI keyboard to NES controller port 2: core 0 hosts USB and runs the NES's upstream
// commands (link.c), core 1 serves the port (port.c).
#include <stdio.h>
#include <string.h>

#include "pico/stdlib.h"
#include "pico/util/queue.h"
#include "tusb.h"

#include "keymap.h"
#include "link.h"
#include "midi.h"
#include "mouse.h"
#include "port.h"

#define REPEAT_DELAY_MS 500
#define REPEAT_MS       33
#define QUEUE_DEPTH     128
#define LINK_DEPTH      1024
#define SYS_DEPTH       4
#define LOG_MS          1000

static queue_t sys, raws, keys, notes, replies, up;
static uint8_t held[6];
static uint8_t rep_key, rep_mods;
static absolute_time_t rep_at;
static bool gui_armed;
static uint8_t locks = LOCK_NUM;
static uint32_t dropped;
static uint8_t kbd_addr, kbd_idx; // kbd_addr 0: no keyboard
static uint8_t leds;              // SET_REPORT buffer, must outlive the transfer
static bool leds_dirty;
static uint32_t raw_reads;
static absolute_time_t raw_idle_at;

// a mouse interface: in report protocol with its layout, or in boot protocol (buttons, dx, dy) when !parsed
struct mouse {
    uint8_t addr, idx; // addr 0: a free slot
    bool parsed;
    struct mouse_layout layout;
};
static struct mouse mice[CFG_TUH_HID];

static struct mouse *mouse_at(uint8_t addr, uint8_t idx) {
    for (int i = 0; i < CFG_TUH_HID; i++)
        if (mice[i].addr == addr && mice[i].idx == idx)
            return &mice[i];
    return NULL;
}

static void emit(uint8_t key, uint8_t mods) {
    uint8_t b[KEYMAP_MAX];
    int n = keymap(key, mods, locks, b);
    for (int i = 0; i < n; i++)
        if (!queue_try_add(&keys, &b[i]))
            dropped++;
}

static bool in(const uint8_t *codes, uint8_t c) {
    return memchr(codes, c, 6) != NULL;
}

static void sys_req(uint8_t req) {
    if (!queue_try_add(&sys, &req))
        dropped++;
}

static void raw(uint8_t usage, bool down) {
    uint16_t ev = usage | (uint16_t)down << 8;
    if (!queue_try_add(&raws, &ev))
        dropped++;
}

// raw mode: every key and modifier going down and up; Alt+F4 still a system request
static void report_raw(const hid_keyboard_report_t *r) {
    for (int b = 0; b < 8; b++)
        if ((r->modifier ^ rep_mods) >> b & 1)
            raw(0xE0 + b, r->modifier >> b & 1);
    for (int i = 0; i < 6; i++)
        if (held[i] >= 0x04 && !in(r->keycode, held[i]))
            raw(held[i], false);
    for (int i = 0; i < 6; i++) {
        uint8_t c = r->keycode[i];
        if (c < 0x04 || in(held, c))
            continue;
        uint8_t req = keymap_sys(c, r->modifier);
        if (req) {
            sys_req(req);
            continue;
        }
        raw(c, true);
    }
    rep_key = 0;
    rep_mods = r->modifier;
    memcpy(held, r->keycode, 6);
}

static void report(const hid_keyboard_report_t *r) {
    uint8_t tap = keymap_tap(&gui_armed, r->modifier, rep_mods, r->keycode);
    if (tap)
        sys_req(tap);
    if (link_rawkeys) {
        report_raw(r);
        return;
    }
    for (int i = 0; i < 6; i++) {
        uint8_t c = r->keycode[i];
        if (c < 0x04 || in(held, c))
            continue;
        uint8_t lock = c == KEYMAP_NUMLOCK ? LOCK_NUM
                     : c == KEYMAP_CAPS    ? LOCK_CAPS
                     : c == KEYMAP_SCROLL  ? LOCK_SCROLL
                                           : 0;
        if (lock) {
            locks ^= lock;
            leds_dirty = true;
            continue;
        }
        printf("key %02x mods %02x\n", c, r->modifier);
        uint8_t req = keymap_sys(c, r->modifier);
        if (req) {
            sys_req(req);
            continue;
        }
        emit(c, r->modifier);
        rep_key = c;
        rep_at = make_timeout_time_ms(REPEAT_DELAY_MS);
    }
    if (rep_key && !in(r->keycode, rep_key))
        rep_key = 0;
    rep_mods = r->modifier;
    memcpy(held, r->keycode, 6);
}

void tuh_hid_mount_cb(uint8_t addr, uint8_t idx, const uint8_t *desc, uint16_t len) {
    uint8_t proto = tuh_hid_interface_protocol(addr, idx);
    printf("hid %u.%u mounted, protocol %u\n", addr, idx, proto);
    if (proto == HID_ITF_PROTOCOL_KEYBOARD) {
        kbd_addr = addr;
        kbd_idx = idx;
        leds_dirty = true;
        tuh_hid_receive_report(addr, idx);
        return;
    }
    struct mouse_layout layout = {0};
    bool parsed = desc && mouse_parse(desc, len, &layout);
    if (proto != HID_ITF_PROTOCOL_MOUSE && !parsed)
        return;
    struct mouse *m = mouse_at(0, 0);
    if (!m)
        return;
    *m = (struct mouse){addr, idx, parsed, layout};
    printf("hid %u.%u mouse: %s, report %u, wheel %u bits\n", addr, idx, parsed ? "parsed" : "boot layout",
           layout.id, parsed ? layout.wheel.size : 0);
    // enumeration left a boot interface in boot protocol, which has no wheel
    if (parsed && tuh_hid_get_protocol(addr, idx) == HID_PROTOCOL_BOOT &&
        tuh_hid_set_protocol(addr, idx, HID_PROTOCOL_REPORT))
        return; // receives once the switch is done
    m->parsed = parsed && tuh_hid_get_protocol(addr, idx) == HID_PROTOCOL_REPORT;
    tuh_hid_receive_report(addr, idx);
}

void tuh_hid_set_protocol_complete_cb(uint8_t addr, uint8_t idx, uint8_t protocol) {
    struct mouse *m = mouse_at(addr, idx);
    if (!m)
        return;
    printf("hid %u.%u %s protocol\n", addr, idx, protocol == HID_PROTOCOL_REPORT ? "report" : "boot");
    m->parsed = m->parsed && protocol == HID_PROTOCOL_REPORT;
    tuh_hid_receive_report(addr, idx);
}

void tuh_hid_umount_cb(uint8_t addr, uint8_t idx) {
    printf("hid %u.%u gone\n", addr, idx);
    if (addr == kbd_addr && idx == kbd_idx) {
        kbd_addr = 0;
        memset(held, 0, sizeof held);
        rep_key = 0;
        gui_armed = false;
    }
    struct mouse *m = mouse_at(addr, idx);
    if (m) {
        m->addr = m->idx = 0;
        port_mouse(0, 0, 0, 0);
    }
}

void tuh_hid_report_received_cb(uint8_t addr, uint8_t idx, const uint8_t *r, uint16_t len) {
    uint8_t proto = tuh_hid_interface_protocol(addr, idx);
    struct mouse *m;
    int dx, dy, wheel;
    uint8_t buttons;
    if (proto == HID_ITF_PROTOCOL_KEYBOARD && len >= sizeof(hid_keyboard_report_t))
        report((const hid_keyboard_report_t *)r);
    else if ((m = mouse_at(addr, idx)) != NULL) {
        if (m->parsed) {
            if (mouse_read(&m->layout, r, len, &dx, &dy, &wheel, &buttons))
                port_mouse(dx, dy, wheel, buttons);
        } else if (len >= 3)
            port_mouse((int8_t)r[1], (int8_t)r[2], 0, r[0]);
    }
    tuh_hid_receive_report(addr, idx);
}

static void raw_idle(void) {
    if (port_reads != raw_reads) {
        raw_reads = port_reads;
        raw_idle_at = make_timeout_time_ms(LINK_RAW_IDLE_MS);
    } else if (link_rawkeys && time_reached(raw_idle_at)) {
        printf("link: raw keys off, port idle\n");
        link_rawkeys = false;
    }
}

// retried each pass: SET_REPORT fails while another control transfer is in flight
static void update_leds(void) {
    if (leds_dirty && kbd_addr) {
        leds = locks;
        if (tuh_hid_set_report(kbd_addr, kbd_idx, 0, HID_REPORT_TYPE_OUTPUT, &leds, 1))
            leds_dirty = false;
    }
}

// repeats wait for the NES to catch up, so a held key never floods the queue
static void repeat(void) {
    if (rep_key && time_reached(rep_at) && queue_get_level(&keys) < KEYMAP_MAX) {
        emit(rep_key, rep_mods);
        rep_at = make_timeout_time_ms(REPEAT_MS);
    }
}

// a line for each group of counters that moved since the last call
static void log_stats(void) {
    static uint32_t reads, sent, lost, ups, packets, drops, events;
    if (port_reads != reads || port_sent != sent || dropped != lost) {
        reads = port_reads;
        sent = port_sent;
        lost = dropped;
        printf("port: %lu reads, %lu words taken, %lu keys dropped\n", (unsigned long)reads, (unsigned long)sent,
               (unsigned long)lost);
    }
    if (port_up != ups || link_packets != packets || link_dropped != drops) {
        ups = port_up;
        packets = link_packets;
        drops = link_dropped;
        printf("link: %lu bytes up (%lu lost), %lu packets, %lu dropped\n", (unsigned long)ups,
               (unsigned long)port_up_lost, (unsigned long)packets, (unsigned long)drops);
    }
    if (midi_events != events) {
        events = midi_events;
        printf("midi: %lu notes, %lu dropped, %lu bad packets\n", (unsigned long)events, (unsigned long)midi_dropped,
               (unsigned long)midi_bad);
    }
}

int main(void) {
    stdio_init_all();
    queue_init(&sys, 1, SYS_DEPTH);
    queue_init(&raws, sizeof(uint16_t), QUEUE_DEPTH);
    queue_init(&keys, 1, QUEUE_DEPTH);
    queue_init(&notes, sizeof(uint16_t), MIDI_DEPTH);
    queue_init(&replies, 1, LINK_DEPTH);
    queue_init(&up, 1, LINK_DEPTH);
    link_init(&up, &replies);
    midi_init(&notes);
    port_start(&sys, &raws, &keys, &notes, &replies, &up);
    const tusb_rhport_init_t host = {.role = TUSB_ROLE_HOST, .speed = TUSB_SPEED_FULL};
    tusb_init(BOARD_TUH_RHPORT, &host);
    printf("usbadapter: USB keyboard, mouse and MIDI -> NES port 2 (D0 GP%d, D3 GP%d, D4 GP%d, OUT0 GP%d, CLK GP%d)\n",
           PORT_PIN_D0, PORT_PIN_D3, PORT_PIN_D4, PORT_PIN_OUT0, PORT_PIN_OE);

    absolute_time_t log_at = make_timeout_time_ms(LOG_MS);
    raw_idle_at = make_timeout_time_ms(LINK_RAW_IDLE_MS);
    for (;;) {
        tuh_task();
        link_poll();
        raw_idle();
        update_leds();
        repeat();
        if (time_reached(log_at)) {
            log_at = make_timeout_time_ms(LOG_MS);
            log_stats();
        }
    }
}
