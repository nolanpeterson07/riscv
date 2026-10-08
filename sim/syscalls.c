#include <errno.h>
#include <sys/stat.h>
#include "uart.h"

#undef errno
extern int errno;

// keep this much room between the heap and the current stack pointer
#define STACK_GUARD 512

extern char _heap_start[];

void _exit(int code) {
    uart_puts("\r\nProgram exited with status code ");
    uart_putdec(code);
    uart_puts("\r\n");

    register int a0 __asm__("a0") = code;
    __asm__ volatile("ebreak" : : "r"(a0));
    for (;;)
        ;
}

int _write(int fd, const char *buf, int len) {
    (void)fd;
    for (int i = 0; i < len; i++) {
        if (buf[i] == '\n')
            uart_putc('\r');
        uart_putc(buf[i]);
    }
    return len;
}

int _read(int fd, char *buf, int len) {
    (void)fd;
    int i = 0;
    while (i < len) {
        char c = uart_getc();
        buf[i++] = c;
        if (c == '\n' || c == '\r')
            break;
    }
    return i;
}

void *_sbrk(int incr) {
    static char *brk = _heap_start;
    char *sp;
    __asm__ volatile("mv %0, sp" : "=r"(sp));
    if (brk + incr > sp - STACK_GUARD) {
        errno = ENOMEM;
        return (void *)-1;
    }
    char *prev = brk;
    brk += incr;
    return prev;
}

int _close(int fd) { (void)fd; return -1; }

int _fstat(int fd, struct stat *st) {
    (void)fd;
    st->st_mode = S_IFCHR;
    return 0;
}

int _isatty(int fd) { (void)fd; return 1; }

int _lseek(int fd, int off, int whence) { (void)fd; (void)off; (void)whence; return 0; }

int _kill(int pid, int sig) { (void)pid; (void)sig; errno = EINVAL; return -1; }

int _getpid(void) { return 1; }
