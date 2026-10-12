#include "uart.h"

void uart_putc(char c) {
    while (UART_STATUS & UART_TX_BUSY)
        ;
    UART_TX = c;
}

int uart_rx_lost;

char uart_getc(void) {
    unsigned status;
    do {
        status = UART_STATUS;
        if (status & UART_OVERRUN)
            uart_rx_lost = 1;
    } while (!(status & UART_RX_VALID));
    return UART_RX;
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
