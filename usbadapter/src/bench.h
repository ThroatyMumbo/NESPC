// The port 2 speed test (desk/speedtest, docs/adapter-link.md): a known pattern down in the layout of one of the
// NES's decoders, and up through the link, timed here.
#ifndef BENCH_H
#define BENCH_H

#include <stdint.h>

#define BENCH_FAST  0 // down, speedtest's 24-cycle decode
#define BENCH_TABLE 1 // down, its 28-cycle table decode
#define BENCH_UP    2 // up, link bytes
#define BENCH_TESTS 3

#define BENCH_PASS    256 // bytes a down pass, 3 reads each
#define BENCH_READS   (BENCH_PASS * 3)
#define BENCH_WAIT_MS 250       // a pass or up burst not started or stalled this long is lost
#define BENCH_NES_HZ  1789773.0 // NTSC CPU, for cycles a byte

struct bench {
    uint32_t us;     // first read to last
    uint32_t bytes;  // moved in `us`
    uint32_t errors; // lost passes; wrong or missing up bytes
};

// pattern byte i (0-255), as speedtest's rbaPattern
static inline uint8_t bench_byte(unsigned i) {
    return (uint8_t)((i * 167 + 29) ^ (i >> 3));
}

#endif
