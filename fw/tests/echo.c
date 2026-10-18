// Reads a line from the UART, then prints it back in upper case.
// Run with: cargo x sim echo --uart-in 'hello riscv\n'
#include "uart.h"

int main(void) {
    for (;;) {
        char line[64];
        int n = 0;
        char c;

        for (;;) {
            c = uart_getc();

            if (c == 0x1D) // ^]
                return uart_rx_lost ? -1 : n;   // -1 if a byte was lost

            if (c == '\n' || c == '\r' || n == (int)sizeof line - 1)
                break;
            uart_putc(c);
            line[n++] = c;
        }
        line[n] = '\0';

        uart_puts("\r\nyou said: ");
        uart_puts(line);
        uart_puts("\r\n");
    }
}
