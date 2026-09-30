#include <memory>
#include <cstdio>
#include <cstdlib>
#include <string>
#include "Vmain.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#include "Vmain___024root.h"

vluint64_t sim_time = 0;

void print_registers(Vmain* dut) {
    for (int i = 0; i < 32; i++) {
        printf("x%-2d = 0x%08x\n", i, dut->rootp->main__DOT__u_register__DOT__registers[i]);
    }
}

void print_memory(Vmain* dut) {
    for (int i = 0; i < 1024; i++) {
        if (dut->rootp->main__DOT__u_mem__DOT__memory[i] != 0) {
            printf("%d: 0x%08x\n", i, dut->rootp->main__DOT__u_mem__DOT__memory[i]);
        }
    }
}

struct UartDecoder {
    enum { IDLE, START, DATA, STOP } state = IDLE;
    int count = 0, bit = 0;
    uint8_t byte = 0;
    std::string out;

    void step(int tx) {
        switch (state) {
        case IDLE:
            if (!tx) { state = START; count = 0; }
            break;
        case START:
            if (++count == UART_CLKS_PER_BIT / 2) {
                if (tx) state = IDLE;   // glitch
                else { state = DATA; count = 0; bit = 0; byte = 0; }
            }
            break;
        case DATA:
            if (++count == UART_CLKS_PER_BIT) {
                count = 0;
                byte |= (tx & 1) << bit;
                if (++bit == 8) state = STOP;
            }
            break;
        case STOP:
            if (++count == UART_CLKS_PER_BIT) {
                if (tx) out += (char)byte;
                else    out += "[framing error]";
                state = IDLE;
            }
            break;
        }
    }
};

static void tick(Vmain* dut, VerilatedVcdC* tfp) {
    // rising edge
    dut->clk = 1;
    dut->eval();
    tfp->dump(sim_time++);

    // falling edge
    dut->clk = 0;
    dut->eval();
    tfp->dump(sim_time++);
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);

    auto dut = std::make_unique<Vmain>();
    auto tfp = std::make_unique<VerilatedVcdC>();

    dut->trace(tfp.get(), 99);
    tfp->open("build/main.vcd");

    dut->rst_n = 0;
    dut->clk   = 0;
    dut->eval();
    tfp->dump(sim_time++);

    tick(dut.get(), tfp.get());   // hold reset through one full clock cycle

    dut->rst_n = 1;

    // run until the program hits ebreak
    const uint32_t EBREAK = 0x00100073;
    const int MAX_CYCLES = argc > 1 ? atoi(argv[1]) : 20;
    UartDecoder uart;
    for (int i = 0; i < MAX_CYCLES; i++) {
        uint32_t inst = dut->rootp->main__DOT__u_iram__DOT__mem[(dut->pc_current_out >> 2) & 1023];
        if (inst == EBREAK) {
            printf("ebreak at pc = 0x%08x, a0 = %d\n", dut->pc_current_out,
                   (int)dut->rootp->main__DOT__u_register__DOT__registers[10]);
            break;
        }
        tick(dut.get(), tfp.get());
        uart.step(dut->uart_tx);
        printf("cycle %2d | pc_current = 0x%08x\n", i, dut->pc_current_out);
    }

    // let the last character finish sending
    for (int i = 0; i < 20 * UART_CLKS_PER_BIT && dut->rootp->main__DOT__uart_tx_busy; i++) {
        tick(dut.get(), tfp.get());
        uart.step(dut->uart_tx);
    }

    tfp->close();
    dut->final();

    print_registers(dut.get());

    print_memory(dut.get());

    if (!uart.out.empty())
        printf("--- uart ---\n%s\n", uart.out.c_str());

    return 0;
}
