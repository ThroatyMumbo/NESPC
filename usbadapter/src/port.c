#include "port.h"

#include <stdlib.h>
#include <string.h>

#include "hardware/pio.h"
#include "pico/multicore.h"
#include "pico/sync.h"
#include "pico/time.h"

#include "kbdword.h"
#include "nespad.pio.h"

volatile uint32_t port_reads;
volatile uint32_t port_sent;
volatile uint32_t port_up;
volatile uint32_t port_up_lost;
struct bench port_bench[BENCH_TESTS];

static PIO pio = pio0, spio = pio1; // spio: nesstream, for the speed test's down passes
static uint sm, ssm, off, soff;
static queue_t *sys, *raws, *keys, *notes, *replies, *up;

static volatile uint32_t bench_down_req; // 1 << 16 | pass << 8 | mode
static volatile uint32_t bench_up_req;   // bytes
static uint32_t up_left, up_n, up_bad, up_first, up_last;
static absolute_time_t up_give_up;

void port_bench_down(uint8_t mode, uint8_t pass) {
    bench_down_req = 1u << 16 | (uint32_t)pass << 8 | mode;
}

void port_bench_up(uint16_t n) {
    bench_up_req = n;
}

static inline uint8_t lines(int d0, int d3, int d4) {
    return (uint8_t)(d3 | d4 << 1 | d0 << 2); // out pindirs order: D3, D4, D0
}

// byte b as 3 reads, undone by speedtest's down_fast or down_table
static void bench_reads(uint8_t mode, uint8_t b, uint8_t r[3]) {
#define B(n) (b >> (n) & 1)
    if (mode == BENCH_FAST) {
        r[0] = lines(B(1), B(7), 0);
        r[1] = lines(B(2), B(5), B(6) ^ 1); // eor $4017's open bus $40 flips bit 6 back
        r[2] = lines(B(0), B(3), B(4));
    } else {
        r[0] = lines(B(0), B(1), B(2));
        r[1] = lines(B(3), B(4), B(5));
        r[2] = lines(B(6), B(7), 0);
    }
#undef B
}

static void data_pins(PIO p) {
    for (uint i = 0; i < 3; i++)
        pio_gpio_init(p, PORT_PIN_D3 + i);
}

// one down pass on nesstream, timed from its first read starting to its last ending; nespad is idle meanwhile
static void bench_down(uint8_t mode, uint8_t pass) {
    static uint32_t words[(BENCH_READS + 9) / 10];
    memset(words, 0, sizeof words);
    for (int i = 0; i < BENCH_PASS; i++) {
        uint8_t r[3];
        bench_reads(mode, bench_byte(i) ^ pass, r);
        for (int j = 0; j < 3; j++) {
            int n = i * 3 + j;
            words[n / 10] |= (uint32_t)r[j] << 3 * (n % 10);
        }
    }
    struct bench *b = &port_bench[mode];

    pio_sm_set_enabled(pio, sm, false);
    pio_sm_exec(pio, sm, pio_encode_set(pio_pindirs, 0));
    pio_sm_restart(spio, ssm);
    pio_sm_clear_fifos(spio, ssm);
    pio_sm_put(spio, ssm, BENCH_READS - 1);
    pio_sm_exec(spio, ssm, pio_encode_pull(false, true));
    pio_sm_exec(spio, ssm, pio_encode_mov(pio_x, pio_osr));
    pio_sm_exec(spio, ssm, pio_encode_out(pio_null, 32)); // OSR empty, so the first out autopulls
    pio_sm_exec(spio, ssm, pio_encode_jmp(soff));
    uint n = 0;
    while (n < count_of(words) && !pio_sm_is_tx_fifo_full(spio, ssm))
        pio_sm_put(spio, ssm, words[n++]);
    data_pins(spio);
    pio_sm_set_enabled(spio, ssm, true);

    uint32_t t0 = 0;
    absolute_time_t give_up = make_timeout_time_ms(BENCH_WAIT_MS);
    for (;;) {
        if (n < count_of(words) && !pio_sm_is_tx_fifo_full(spio, ssm))
            pio_sm_put(spio, ssm, words[n++]);
        if (!pio_sm_is_rx_fifo_empty(spio, ssm)) {
            uint32_t now = time_us_32();
            if (pio_sm_get(spio, ssm) == 0) {
                t0 = now;
                give_up = make_timeout_time_ms(BENCH_WAIT_MS);
            } else {
                b->us += now - t0;
                b->bytes += BENCH_PASS;
                break;
            }
        }
        if (time_reached(give_up)) {
            b->errors++;
            break;
        }
    }

    pio_sm_set_enabled(spio, ssm, false);
    pio_sm_exec(spio, ssm, pio_encode_set(pio_pindirs, 0));
    data_pins(pio);
    pio_sm_restart(pio, sm);
    pio_sm_clear_fifos(pio, sm);
    pio_sm_exec(pio, sm, pio_encode_jmp(off));
    pio_sm_set_enabled(pio, sm, true);
}

static void bench_up_end(void) {
    struct bench *b = &port_bench[BENCH_UP];
    b->errors += up_bad + up_left;
    if (up_n > 1) {
        b->us += up_last - up_first;
        b->bytes += up_n - 1;
    }
    up_left = 0;
}

// an upstream byte of the speed test: timed, checked against the pattern and kept off the link
static void bench_up_byte(uint8_t b) {
    uint32_t now = time_us_32();
    if (!up_n)
        up_first = now;
    up_last = now;
    up_bad += b != bench_byte(up_n & 255);
    up_n++;
    up_give_up = make_timeout_time_ms(BENCH_WAIT_MS);
    if (!--up_left)
        bench_up_end();
}

static critical_section_t mouse_lock;
static int mouse_x, mouse_y, mouse_wheel; // counts not yet sent
static uint8_t mouse_buttons, mouse_sent_buttons;

void port_mouse(int dx, int dy, int wheel, uint8_t buttons) {
    critical_section_enter_blocking(&mouse_lock);
    mouse_x += dx;
    mouse_y += dy;
    mouse_wheel -= wheel;
    mouse_buttons = buttons & 3;
    critical_section_exit(&mouse_lock);
}

static int take(int *acc) {
    int d = *acc / PORT_MOUSE_DIV;
    if (abs(d) > KBDWORD_D_MAX)
        d = d < 0 ? -KBDWORD_D_MAX : KBDWORD_D_MAX;
    *acc -= d * PORT_MOUSE_DIV;
    return d;
}

// a wheel word, then a mouse word for what moved or changed since the last one, if anything did
static bool mouse_word(uint8_t seq, uint32_t *w) {
    critical_section_enter_blocking(&mouse_lock);
    if (mouse_wheel) {
        int n = mouse_wheel < -127 ? -127 : mouse_wheel > 127 ? 127 : mouse_wheel;
        mouse_wheel -= n;
        critical_section_exit(&mouse_lock);
        *w = wheelword(seq, n);
        return true;
    }
    int dx = take(&mouse_x), dy = take(&mouse_y);
    uint8_t b = mouse_buttons;
    bool any = dx || dy || b != mouse_sent_buttons;
    mouse_sent_buttons = b;
    critical_section_exit(&mouse_lock);
    if (any)
        *w = mouseword(seq, dx, dy, b);
    return any;
}

// a word leaves only once a read of it has run to the end; seq lets the NES drop repeats
static void serve(void) {
    uint8_t seq = 0, b;
    uint16_t ev;
    uint32_t cur = kbdword(seq, 0);
    uint32_t cur_s = kbdstream(cur); // as the PIO shifts it, and pushes it back once read
    bool pending = false;            // cur holds a word the NES has not taken
    pio_sm_put_blocking(pio, sm, cur_s);
    for (;;) {
        uint32_t req = bench_down_req;
        if (req) {
            bench_down_req = 0;
            bench_down(req & 0xff, req >> 8 & 0xff);
            pio_sm_put_blocking(pio, sm, cur_s);
        }
        if (bench_up_req) {
            up_left = bench_up_req;
            bench_up_req = 0;
            up_n = up_bad = 0;
            up_give_up = make_timeout_time_ms(BENCH_WAIT_MS);
        }
        if (up_left && time_reached(up_give_up))
            bench_up_end();
        uint32_t next = cur;
        while (!pio_sm_is_rx_fifo_empty(pio, sm)) {
            uint32_t got = pio_sm_get(pio, sm);
            if ((got & nespad_UP_TAG) == nespad_UP_TAG) {
                b = got >> 24;
                port_up++;
                if (up_left) {
                    bench_up_byte(b);
                    continue;
                }
                if (!queue_try_add(up, &b))
                    port_up_lost++;
                continue;
            }
            port_reads++;
            if (got == cur_s && pending) {
                port_sent++;
                next = kbdword(seq, 0);
                pending = false;
            }
        }
        if (!pending) {
            if (queue_try_remove(sys, &b)) {
                next = sysword(++seq, b);
                pending = true;
            } else if (queue_try_remove(raws, &ev)) {
                next = rawword(++seq, ev & 0xff, ev >> 8);
                pending = true;
            } else if (queue_try_remove(keys, &b)) {
                next = kbdword(++seq, b);
                pending = true;
            } else if (queue_try_remove(notes, &ev)) {
                next = midiword(++seq, ev & 0x7f, ev >> 7 & 1, ev >> 8);
                pending = true;
            } else if (queue_try_remove(replies, &b)) {
                next = replyword(++seq, b);
                pending = true;
            } else if (mouse_word(seq + 1, &next)) {
                seq++;
                pending = true;
            }
        }
        if (next != cur) {
            cur = next;
            cur_s = kbdstream(cur);
            pio_sm_put_blocking(pio, sm, cur_s);
        }
    }
}

void port_start(queue_t *s, queue_t *rk, queue_t *k, queue_t *n, queue_t *r, queue_t *u) {
    sys = s;
    raws = rk;
    keys = k;
    notes = n;
    replies = r;
    up = u;
    critical_section_init(&mouse_lock);
    sm = pio_claim_unused_sm(pio, true);
    off = pio_add_program(pio, &nespad_program);
    nespad_program_init(pio, sm, off, PORT_PIN_D3, PORT_PIN_OUT0, PORT_PIN_OE, KBDWORD_BITS);
    ssm = pio_claim_unused_sm(spio, true);
    soff = pio_add_program(spio, &nesstream_program);
    nesstream_program_init(spio, ssm, soff, PORT_PIN_D3, PORT_PIN_OUT0, PORT_PIN_OE);
    pio_sm_set_enabled(pio, sm, true);
    multicore_launch_core1(serve);
}
