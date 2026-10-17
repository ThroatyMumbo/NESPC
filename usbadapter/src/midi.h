// USB MIDI keyboards: note on and off go on `notes` as uint16_t, low byte on << 7 | note, high byte velocity.
#ifndef MIDI_H
#define MIDI_H

#include <stdint.h>
#include "pico/util/queue.h"

#define MIDI_DEPTH 64

void midi_init(queue_t *notes);

extern uint32_t midi_events;  // notes queued
extern uint32_t midi_dropped; // notes `notes` had no room for
extern uint32_t midi_bad;     // malformed packets

#endif
