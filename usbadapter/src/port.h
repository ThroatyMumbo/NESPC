// NES controller port 2 on core 1: a word per complete read (11 $4017 reads), from `sys`, `raws`, `keys`, `notes`,
// `replies`, then mouse motion, in that priority; the bytes the NES sends upstream go on `up`.
#ifndef PORT_H
#define PORT_H

#include <stdint.h>
#include "pico/util/queue.h"

#include "bench.h"

#define PORT_PIN_D3   5 // NES port pin 5, D3; D4 and D0 follow, as nespad.pio drives them together
#define PORT_PIN_D4   6 // pin 6, D4
#define PORT_PIN_D0   7 // pin 4, D0
#define PORT_PIN_OUT0 3 // pin 3, OUT0 (strobe)
#define PORT_PIN_OE   4 // pin 2, CLK: $4017 read strobe

#define PORT_MOUSE_DIV 4 // mouse counts per NES pixel

// queues of uint8_t, except `raws` (uint16_t usage | down << 8) and `notes` (midi.h)
void port_start(queue_t *sys, queue_t *raws, queue_t *keys, queue_t *notes, queue_t *replies, queue_t *up);

// from core 0: a mouse report's motion, wheel (positive away from the user) and buttons (bit 0 left, bit 1 right)
void port_mouse(int dx, int dy, int wheel, uint8_t buttons);

// from core 0: run one down pass of the speed test in `mode` (BENCH_FAST, BENCH_TABLE), or time the next n upstream bytes
void port_bench_down(uint8_t mode, uint8_t pass);
void port_bench_up(uint16_t n);

extern struct bench port_bench[BENCH_TESTS]; // core 1 adds, link.c reports and clears

extern volatile uint32_t port_reads;   // complete reads of a word
extern volatile uint32_t port_sent;    // key, note, reply and mouse words the NES has taken
extern volatile uint32_t port_up;      // upstream bytes received
extern volatile uint32_t port_up_lost; // upstream bytes `up` had no room for

#endif
