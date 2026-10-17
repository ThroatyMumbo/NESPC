#include "link.h"

#include <stdio.h>
#include <string.h>

#include "pico/time.h"

#include "port.h"

volatile bool link_rawkeys;
uint32_t link_packets;
uint32_t link_dropped;

static queue_t *up, *replies;
static enum { CMD, LEN, DATA } state;
static uint8_t cmd, len, n;
static uint8_t buf[255];
static absolute_time_t stall_at;

// the speed test's results since the last report, a record each, then cleared
static bool bench_report(void) {
    static const char *const names[BENCH_TESTS] = {"down fast ", "down table", "up        "};
    uint32_t nes[BENCH_TESTS] = {buf[1] | buf[2] << 8, buf[3] | buf[4] << 8, 0};
    for (int t = 0; t < BENCH_TESTS; t++) {
        struct bench *b = &port_bench[t];
        uint32_t err = MIN(b->errors + nes[t], 999999u);
        char s[LINK_BENCH_RECORD + 1];
        if (b->us && b->bytes) {
            double kbs = b->bytes * 1000.0 / b->us;
            double cyc = b->us * (BENCH_NES_HZ / 1e6) / b->bytes;
            snprintf(s, sizeof s, "%5.1f%5.1f%6lu", MIN(kbs, 999.9), MIN(cyc, 999.9), (unsigned long)err);
        } else {
            snprintf(s, sizeof s, "  ---  ---%6lu", (unsigned long)err);
        }
        printf("bench: %s %lu bytes in %lu us, %lu errors: %s\n", names[t], (unsigned long)b->bytes,
               (unsigned long)b->us, (unsigned long)err, s);
        memset(b, 0, sizeof *b);
        for (int i = 0; i < LINK_BENCH_RECORD; i++)
            if (!queue_try_add(replies, &s[i]))
                return false;
    }
    return true;
}

static bool bench(void) {
    if (len < 1)
        return false;
    switch (buf[0]) {
    case LINK_BENCH_DOWN:
        if (len < 3 || buf[1] > BENCH_TABLE)
            return false;
        port_bench_down(buf[1], buf[2]);
        return true;
    case LINK_BENCH_UP:
        if (len < 3)
            return false;
        port_bench_up(buf[1] | buf[2] << 8);
        return true;
    case LINK_BENCH_REPORT:
        return len >= 5 && bench_report();
    }
    return false;
}

static void run(void) {
    switch (cmd) {
    case LINK_BENCH:
        if (!bench()) {
            link_dropped++;
            return;
        }
        break;
    case LINK_ECHO:
        for (int i = 0; i < len; i++)
            if (!queue_try_add(replies, &buf[i])) {
                link_dropped++;
                return;
            }
        break;
    case LINK_RAWKEYS:
        if (len < 1) {
            link_dropped++;
            return;
        }
        if (link_rawkeys != (buf[0] != 0))
            printf("link: raw keys %s\n", buf[0] ? "on" : "off");
        link_rawkeys = buf[0] != 0;
        break;
    default:
        printf("link: unknown command %02x, %u bytes\n", cmd, len);
        link_dropped++;
        return;
    }
    link_packets++;
}

void link_init(queue_t *u, queue_t *r) {
    up = u;
    replies = r;
}

void link_poll(void) {
    uint8_t b;
    if (state != CMD && time_reached(stall_at)) {
        printf("link: command %02x stalled at %u of %u bytes\n", cmd, n, len);
        state = CMD;
        link_dropped++;
    }
    while (queue_try_remove(up, &b)) {
        stall_at = make_timeout_time_ms(LINK_TIMEOUT_MS);
        switch (state) {
        case CMD:
            cmd = b;
            state = LEN;
            break;
        case LEN:
            len = b;
            n = 0;
            state = DATA;
            break;
        case DATA:
            buf[n++] = b;
            break;
        }
        if (state == DATA && n == len) {
            run();
            state = CMD;
        }
    }
}
