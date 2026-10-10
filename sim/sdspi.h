#ifndef SDSPI_H
#define SDSPI_H

#include <stdint.h>
#include <stddef.h>

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

// Send one command frame and return its R1 reply (0xFF = no reply)
static inline unsigned char sdspi_cmd(sdspi_t *s, unsigned char cmd, unsigned arg, unsigned char crc) {
    sdspi_xfer(s, 0xFF);
    sdspi_xfer(s, 0x40 | cmd);
    sdspi_xfer(s, arg >> 24);
    sdspi_xfer(s, arg >> 16);
    sdspi_xfer(s, arg >> 8);
    sdspi_xfer(s, arg);
    sdspi_xfer(s, crc);

    // reply arrives within 8 bytes, MSB of R1 is always 0
    for (int i = 0; i < 8; i++) {
        unsigned char r = sdspi_xfer(s, 0xFF);
        if (!(r & 0x80))
            return r;
    }
    return 0xFF;
}

// Cards in the wild this supports: SDHC and SDXC only (block addressing, block n is argument n)
static inline int sdspi_init(sdspi_t *s) {
    s->ctrl = SDSPI_CS_N;
    sdspi_set_div(s, 34);

    // 74+ clocks with cs high so the card powers up
    for (int i = 0; i < 10; i++)
        sdspi_xfer(s, 0xFF);

    sdspi_select(s, 1);

    int ok = 0;
    unsigned char r7[4];

    // CMD0: reset, enter SPI mode
    // CMD8: voltage check, only v2+ cards answer. r7[2:3] echoes 0x1AA.
    if (sdspi_cmd(s, 0, 0, 0x95) == 0x01 && sdspi_cmd(s, 8, 0x1AA, 0x87) == 0x01) {
        for (int i = 0; i < 4; i++)
            r7[i] = sdspi_xfer(s, 0xFF);

        // ACMD41 (CMD55 then CMD41) with HCS until the card leaves idle
        if (r7[2] == 0x01 && r7[3] == 0xAA) {
            for (int i = 0; i < 10000 && !ok; i++) {
                sdspi_cmd(s, 55, 0, 0x01);
                ok = sdspi_cmd(s, 41, 0x40000000, 0x01) == 0x00;
            }
        }
    }

    sdspi_select(s, 0);
    sdspi_xfer(s, 0xFF); // card releases miso on the next clock after cs rises

    // 27 MHz / (2 * 4) = ~3.4 MHz; card allows 25 MHz
    sdspi_set_div(s, 4);
    return ok ? 0 : -1;
}

static inline int sdspi_read_block(sdspi_t *s, uint32_t lba, uint8_t *buf) {
    int r = -1;

    sdspi_select(s, 1);

    if (sdspi_cmd(s, 17, lba, 0x01) == 0x00) { // CRC ignored
        unsigned char t = 0xFF;
        for (int i = 0; i < 100000 && t == 0xFF; i++)
            t = sdspi_xfer(s, 0xFF);

        if (t == 0xFE) {
            for (int i = 0; i < 512; i++)
                buf[i] = sdspi_xfer(s, 0xFF);
            sdspi_xfer(s, 0xFF); // discard CRC
            sdspi_xfer(s, 0xFF);
            r = 0;
        }
    }

    sdspi_select(s, 0);
    sdspi_xfer(s, 0xFF);
    return r;
}

#endif
