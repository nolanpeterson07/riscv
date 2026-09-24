#include <memory>
#include <cstdio>
#include "Vmain.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

vluint64_t sim_time = 0;

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

    const int NUM_CYCLES = 20;
    for (int i = 0; i < NUM_CYCLES; i++) {
        tick(dut.get(), tfp.get());
        printf("cycle %2d | pc_current = 0x%08x\n", i, dut->pc_current_out);
    }

    tfp->close();
    dut->final();

    return 0;
}
