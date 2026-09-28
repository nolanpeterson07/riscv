# Startup for C programs: set up the stack, call main, then spin.
.section .text
.globl _start
_start:
    li   sp, 4096
    call main
1:  j    1b
