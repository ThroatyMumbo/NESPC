// Commands the NES sends upstream: cmd, len, len bytes (docs/adapter-link.md); answers go back as reply words.
#ifndef LINK_H
#define LINK_H

#include <stdbool.h>
#include <stdint.h>
#include "pico/util/queue.h"

#define LINK_ECHO    0x01 // the payload comes back as replies
#define LINK_RAWKEYS 0x02 // 1 byte, 1 on: keys go out as usages down and up (KBDWORD_RAW) instead of ASCII
#define LINK_BENCH   0x03 // the speed test (bench.h): op, then its bytes (LINK_BENCH_*)

#define LINK_BENCH_DOWN   0 // mode, pass: the next strobe takes a down pass
#define LINK_BENCH_UP     1 // n lo, n hi: the next n upstream bytes are the pattern
#define LINK_BENCH_REPORT 2 // NES errors fast lo, hi, table lo, hi: replies, LINK_BENCH_RECORD bytes a test
#define LINK_BENCH_RECORD 16 // ASCII: KB/s %5.1f, cycles a byte %5.1f, errors %6lu

#define LINK_RAW_IDLE_MS 500 // raw mode ends once the port goes this long unread, so the next program gets ASCII

#define LINK_TIMEOUT_MS 250 // a packet stalled this long is dropped, so a lost byte costs one packet

void link_init(queue_t *up, queue_t *replies);
void link_poll(void);

extern volatile bool link_rawkeys;
extern uint32_t link_packets; // run
extern uint32_t link_dropped; // timed out, unknown, or replies with no room

#endif
