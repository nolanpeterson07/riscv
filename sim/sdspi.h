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

#endif