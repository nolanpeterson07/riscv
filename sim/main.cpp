#include "Valu.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#include <cstdio>
#include <iomanip>
#include <iostream>

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);

    Valu *dut = new Valu;

    Verilated::traceEverOn(true);
    VerilatedVcdC *tfp = new VerilatedVcdC;
    dut->trace(tfp, 99);
    tfp->open("alu_verilator.vcd");

    vluint64_t time = 0;

    dut->op = 0;
    dut->operand_a = 10;
    dut->operand_b = 15;

    dut->eval();
    tfp->dump(time++);

    std::cout << std::setw(15) << "operand a" << std::setw(15) << "operand b" << std::setw(15) << "op" << std::endl;
    std::cout << std::setw(15) << dut->operand_a << std::setw(15) << dut->operand_b << std::setw(15) << dut->op << std::endl;

    printf("Result: %d\n", dut->result);

    tfp->close();
    delete dut;
    return 0;
}
