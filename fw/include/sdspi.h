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

// lba to command argument: 9 when the card is byte addressed (SDSC), set by sdspi_init
static int sdspi_shift;

// Deselect and pass r through
static inline int sdspi_release(sdspi_t *s, int r) {
    sdspi_select(s, 0);
    sdspi_xfer(s, 0xFF); // card releases miso on the next clock after cs rises
    return r;
}

// Clock until the card releases miso (0xFF)
static inline int sdspi_wait_ready(sdspi_t *s) {
    for (int i = 0; i < 500000; i++)
        if (sdspi_xfer(s, 0xFF) == 0xFF)
            return 0;
    return -1;
}

// Send one command frame and return its R1 reply (0xFF = no reply)
static inline unsigned char sdspi_cmd(sdspi_t *s, unsigned char cmd, unsigned arg, unsigned char crc) {
    // CMD0 has to go out even if the card is in an unknown state
    if (cmd == 0)
        sdspi_xfer(s, 0xFF);
    else if (sdspi_wait_ready(s) != 0)
        return 0xFF;
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

// Wait for the 0xFE data token, then read n bytes and discard the CRC
static inline int sdspi_read_data(sdspi_t *s, uint8_t *buf, int n) {
    unsigned char t = 0xFF;
    for (int i = 0; i < 100000 && t == 0xFF; i++)
        t = sdspi_xfer(s, 0xFF);
    if (t != 0xFE)
        return -1;

    for (int i = 0; i < n; i++)
        buf[i] = sdspi_xfer(s, 0xFF);
    sdspi_xfer(s, 0xFF);
    sdspi_xfer(s, 0xFF);
    return 0;
}

// Supports v2 cards only
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

    // CMD58: read OCR, CCS (bit 30) set means block addressing
    if (ok) {
        ok = sdspi_cmd(s, 58, 0, 0x01) == 0x00;
        for (int i = 0; i < 4; i++)
            r7[i] = sdspi_xfer(s, 0xFF);
        sdspi_shift = r7[0] & 0x40 ? 0 : 9;

        // CMD16: byte addressed cards need the block length fixed at 512
        if (ok && sdspi_shift)
            ok = sdspi_cmd(s, 16, 512, 0x01) == 0x00;
    }

    sdspi_release(s, 0);

    // 27 MHz / (2 * 4) = ~3.4 MHz; card allows 25 MHz
    sdspi_set_div(s, 4);
    return ok ? 0 : -1;
}

static inline int sdspi_read_block(sdspi_t *s, uint32_t lba, uint8_t *buf) {
    int r = -1;

    sdspi_select(s, 1);

    if (sdspi_cmd(s, 17, lba << sdspi_shift, 0x01) == 0x00) // CRC ignored
        r = sdspi_read_data(s, buf, 512);

    return sdspi_release(s, r);
}

static inline int sdspi_write_block(sdspi_t *s, uint32_t lba, const uint8_t *buf) {
    int r = -1;

    sdspi_select(s, 1);

    if (sdspi_cmd(s, 24, lba << sdspi_shift, 0x01) == 0x00) {
        sdspi_xfer(s, 0xFF);
        sdspi_xfer(s, 0xFE); // data token
        for (int i = 0; i < 512; i++)
            sdspi_xfer(s, buf[i]);
        sdspi_xfer(s, 0xFF); // dummy CRC
        sdspi_xfer(s, 0xFF);

        // data response xxx00101 = accepted, then the card is busy
        if ((sdspi_xfer(s, 0xFF) & 0x1F) == 0x05)
            r = sdspi_wait_ready(s);
    }

    return sdspi_release(s, r);
}

// Block until any pending write has finished
static inline int sdspi_sync(sdspi_t *s) {
    sdspi_select(s, 1);
    return sdspi_release(s, sdspi_wait_ready(s));
}

// Card size in 512 byte sectors
static inline int sdspi_sector_count(sdspi_t *s, uint32_t *count) {
    int r = -1;
    uint8_t csd[16];

    sdspi_select(s, 1);

    if (sdspi_cmd(s, 9, 0, 0x01) == 0x00)
        r = sdspi_read_data(s, csd, 16);

    if (sdspi_release(s, r) != 0)
        return -1;

    if (csd[0] >> 6 == 1) { // CSD v2: C_SIZE in units of 512 KiB
        uint32_t c_size = ((uint32_t)(csd[7] & 0x3F) << 16) | (csd[8] << 8) | csd[9];
        *count = (c_size + 1) << 10;
    } else { // CSD v1
        uint32_t c_size = ((uint32_t)(csd[6] & 0x03) << 10) | (csd[7] << 2) | (csd[8] >> 6);
        int mult = ((csd[9] & 0x03) << 1) | (csd[10] >> 7);
        int bl_len = csd[5] & 0x0F;
        *count = (c_size + 1) << (mult + 2 + bl_len - 9);
    }
    return 0;
}

#endif
