#ifndef SDSPI_H
#define SDSPI_H

typedef struct {
    volatile unsigned data;    // +0 write: send byte, read: last received byte
    volatile unsigned status;  // +4 bit0 busy
    volatile unsigned ctrl;    // +8 bit0 cs_n
    volatile unsigned div;     // +C sck = clk / (2 * div)
} sdspi_t;

#define SDSPI ((sdspi_t *)0x20000000)

#define SDSPI_BUSY (1u << 0)
#define SDSPI_CS_N (1u << 0)

static inline unsigned char sdspi_xfer(sdspi_t *s, unsigned char b) {
    while (s->status & SDSPI_BUSY)
        ;
    s->data = b;
    while (s->status & SDSPI_BUSY)
        ;
    return (unsigned char)s->data;
}

static inline void sdspi_select(sdspi_t *s, int on) {
    s->ctrl = on ? 0 : SDSPI_CS_N;
}

static inline void sdspi_set_div(sdspi_t *s, unsigned div) {
    s->div = div;
}

#endif
