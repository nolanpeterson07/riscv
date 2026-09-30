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

struct UartEncoder {
    std::string in;
    size_t pos = 0;
    int cycle = 0;

    int step() {
        const int idle = 2 * UART_CLKS_PER_BIT;
        const int frame = 10 * UART_CLKS_PER_BIT;
        int t = cycle++ - idle;
        if (t < 0 || pos >= in.size())
            return 1;
        int bit = t % frame / UART_CLKS_PER_BIT;   // 0 = start, 1..8 = data, 9 = stop
        int level = bit == 0 ? 0 : bit == 9 ? 1 : ((uint8_t)in[pos] >> (bit - 1)) & 1;
        if (t % frame == frame - 1)
            pos++;
        return level;
    }
};

// "\n", "\r", "\t" and "\\" in the terminal text become real characters
static std::string unescape(const char* s) {
    std::string out;
    for (; *s; s++) {
        if (*s == '\\' && s[1]) {
            s++;
            out += *s == 'n' ? '\n' : *s == 'r' ? '\r' : *s == 't' ? '\t' : *s;
        } else {
            out += *s;
        }
    }
    return out;
}

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

    UartEncoder uart_in;
    if (argc > 2)
        uart_in.in = unescape(argv[2]);

    dut->rst_n   = 0;
    dut->clk     = 0;
    dut->uart_rx = 1;   // idle high
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
        dut->uart_rx = uart_in.step();
        tick(dut.get(), tfp.get());
        uart.step(dut->uart_tx);
        printf("cycle %2d | pc_current = 0x%08x\n", i, dut->pc_current_out);
    }

    // let the last character finish sending
    for (int i = 0; i < 20 * UART_CLKS_PER_BIT && dut->rootp->main__DOT__uart_tx_busy; i++) {
        dut->uart_rx = uart_in.step();
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
