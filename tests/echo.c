// Reads a line from the UART, then prints it back in upper case.
// Run with: make TEST=tests/echo.c UART_IN='hello riscv\n'
#include "uart.h"

int main(void) {
    char line[64];
    int n = 0;
    char c;

    for (;;) {
        c = uart_getc();
        if (c == '\n' || n == (int)sizeof line - 1)
            break;
        line[n++] = c;
    }
    line[n] = '\0';

    for (int i = 0; i < n; i++)
        if (line[i] >= 'a' && line[i] <= 'z')
            line[i] -= 'a' - 'A';

    uart_puts("you said: ");
    uart_puts(line);
    uart_putc('\n');

    return uart_rx_lost ? -1 : n;   // -1 if a byte was lost
}
