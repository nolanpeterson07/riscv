// Minimal string.h routines. gcc emits calls to these for struct copies and
// array initialization even with -ffreestanding.
#include <stddef.h>

void *memset(void *dst, int c, size_t n) {
    unsigned char *d = dst;
    while (n--)
        *d++ = (unsigned char)c;
    return dst;
}

void *memcpy(void *dst, const void *src, size_t n) {
    unsigned char *d = dst;
    const unsigned char *s = src;
    while (n--)
        *d++ = *s++;
    return dst;
}

void *memmove(void *dst, const void *src, size_t n) {
    unsigned char *d = dst;
    const unsigned char *s = src;
    if (d < s) {
        while (n--)
            *d++ = *s++;
    } else {
        d += n;
        s += n;
        while (n--)
            *--d = *--s;
    }
    return dst;
}

int memcmp(const void *a, const void *b, size_t n) {
    const unsigned char *x = a, *y = b;
    for (; n--; x++, y++)
        if (*x != *y)
            return *x - *y;
    return 0;
}

#include "uart.h"

void uart_putc(char c) {
    while (UART_STATUS & UART_TX_BUSY)
        ;
    UART_TX = c;
}

char uart_getc(void) {
    while (!(UART_STATUS & UART_RX_VALID))
        ;
    return UART_RX;          // reading RX clears rx_valid
}

void uart_puts(const char *s) {
    while (*s)
        uart_putc(*s++);
}

void uart_puthex(unsigned x) {
    uart_puts("0x");
    for (int shift = 28; shift >= 0; shift -= 4)
        uart_putc("0123456789abcdef"[(x >> shift) & 0xf]);
}

void uart_putdec(int x) {
    char buf[12];
    int i = 0;
    unsigned u = x < 0 ? -(unsigned)x : (unsigned)x;
    do {
        buf[i++] = '0' + u % 10;
        u /= 10;
    } while (u);
    if (x < 0)
        uart_putc('-');
    while (i)
        uart_putc(buf[--i]);
}
