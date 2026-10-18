#ifndef TIMER_H
#define TIMER_H

#include <stdint.h>

typedef struct {
    volatile unsigned lo;
    volatile unsigned hi;
} timer_t;

#define TIMER ((timer_t *)0x30000000)

static inline uint64_t timer_cycles(void) {
    uint32_t lo = TIMER->lo; // latches hi
    uint32_t hi = TIMER->hi;
    return ((uint64_t)hi << 32) | lo;
}

static inline uint64_t timer_ms_since_boot(void) {
    return timer_cycles() / 27000;
}

#endif
