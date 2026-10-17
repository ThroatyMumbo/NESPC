#include "midi.h"

#include <stdio.h>
#include <string.h>

#include "tusb.h"

#define CIN_NOTE_OFF 0x8
#define CIN_NOTE_ON  0x9
#define CIN_CC       0xB
#define CC_SOUND_OFF 120
#define CC_NOTES_OFF 123

uint32_t midi_events;
uint32_t midi_dropped;
uint32_t midi_bad;

static queue_t *notes;
static uint8_t held[CFG_TUH_MIDI][16]; // a bit per note, so an unplugged keyboard leaves nothing sounding
static uint8_t cables[CFG_TUH_MIDI];

static void put(uint8_t idx, uint8_t note, bool on, uint8_t vel) {
    uint8_t bit = 1 << (note & 7);
    if (on)
        held[idx][note >> 3] |= bit;
    else
        held[idx][note >> 3] &= ~bit;
    printf("midi %u: note %u %s %u\n", idx, note, on ? "on" : "off", vel);
    uint16_t ev = (uint16_t)(on << 7 | note) | (uint16_t)vel << 8;
    if (queue_try_add(notes, &ev))
        midi_events++;
    else
        midi_dropped++;
}

static void release(uint8_t idx) {
    for (int note = 0; note < 128; note++)
        if (held[idx][note >> 3] & 1 << (note & 7))
            put(idx, note, false, 0);
}

// a USB-MIDI packet as the spec has it; the Alesis 13b2:0063 sends 64 random bytes on a cold plug-in
static bool valid(uint8_t idx, const uint8_t p[4]) {
    uint8_t cin = p[0] & 15;
    if (p[0] >> 4 >= cables[idx])
        return false;
    if (cin == CIN_NOTE_OFF || cin == CIN_NOTE_ON || cin == CIN_CC)
        return p[1] >> 4 == cin && !((p[2] | p[3]) & 0x80);
    return true;
}

void tuh_midi_mount_cb(uint8_t idx, const tuh_midi_mount_cb_t *m) {
    uint16_t vid = 0, pid = 0;
    tuh_vid_pid_get(m->daddr, &vid, &pid);
    printf("midi %u mounted: %04x:%04x addr %u, interface %u, %u cables in\n", idx, vid, pid, m->daddr,
           m->bInterfaceNumber, m->rx_cable_count);
    memset(held[idx], 0, sizeof held[idx]);
    cables[idx] = m->rx_cable_count ? m->rx_cable_count : 1;
}

void tuh_midi_umount_cb(uint8_t idx) {
    printf("midi %u gone\n", idx);
    release(idx);
}

// once a packet is malformed, the rest of what is waiting is not trusted either
void tuh_midi_rx_cb(uint8_t idx, uint32_t xferred_bytes) {
    (void)xferred_bytes;
    uint8_t p[4];
    bool bad = false;
    while (tuh_midi_packet_read(idx, p)) {
        if (bad || !(p[0] | p[1] | p[2] | p[3]))
            continue;
        if (!valid(idx, p)) {
            printf("midi %u: bad packet %02x %02x %02x %02x, rest dropped\n", idx, p[0], p[1], p[2], p[3]);
            midi_bad++;
            bad = true;
            continue;
        }
        uint8_t cin = p[0] & 15;
        if (cin == CIN_NOTE_ON)
            put(idx, p[2], p[3] != 0, p[3]);
        else if (cin == CIN_NOTE_OFF)
            put(idx, p[2], false, p[3]);
        else if (cin == CIN_CC && (p[2] == CC_SOUND_OFF || p[2] == CC_NOTES_OFF))
            release(idx);
    }
}

void midi_init(queue_t *q) {
    notes = q;
}
