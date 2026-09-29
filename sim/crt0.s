# Startup for C programs: set up the stack, call main, then stop the sim.
.section .text
.globl _start
_start:
    li   sp, 4096        # top of the 4 KiB data memory
    call main
    ebreak               # sim stops here; main's return value is in a0
