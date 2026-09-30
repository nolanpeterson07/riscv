#ifndef UART_H
#define UART_H

#define UART_TX     (*(volatile unsigned *)0x10000000)
#define UART_STATUS (*(volatile unsigned *)0x10000004)
#define UART_RX     (*(volatile unsigned *)0x10000008)

#define UART_TX_BUSY  (1u << 0)
#define UART_RX_VALID (1u << 1)
#define UART_OVERRUN  (1u << 2)

void uart_putc(char c);
void uart_puts(const char *s);
void uart_puthex(unsigned x);
void uart_putdec(int x);
char uart_getc(void);

#endif
