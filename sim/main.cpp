#include "Valu.h"
#include "Vdecoder.h"
#include "Vregister.h"
#include "verilated.h"
#include <cassert>
#include <cstdio>

static void test_alu(Valu &dut, uint32_t a, uint32_t b, uint8_t op, uint32_t expected) {
    dut.operand_a = a;
    dut.operand_b = b;
    dut.op = op;
    dut.eval();
    printf("alu op=%u a=%u b=%u -> result=%u\n", op, a, b, dut.result);
    assert(dut.result == expected);
}

static void test_decoder(Vdecoder &dut, uint32_t inst, uint32_t opcode, uint32_t funct3,
                          uint32_t funct7, uint32_t rs1, uint32_t rs2, uint32_t rd, uint32_t imm) {
    dut.inst = inst;
    dut.eval();
    printf("decoder inst=0x%08x -> opcode=0x%x rd=%u imm=%d\n", inst, dut.opcode, dut.rd, (int32_t)dut.imm);
    assert(dut.opcode == opcode);
    assert(dut.funct3 == funct3);
    assert(dut.funct7 == funct7);
    assert(dut.rs1 == rs1);
    assert(dut.rs2 == rs2);
    assert(dut.rd == rd);
    assert(dut.imm == imm);
}

static void test_registers(Vregister &dut) {
    dut.clk = 0;
    dut.rst_n = 0;
    dut.eval();

    dut.rst_n = 1;
    dut.rd_write_en = 1;
    dut.rd_addr = 1;
    dut.rd_data = 42;
    dut.rs1_addr = 1;
    dut.rs2_addr = 2;

    dut.clk = 1;
    dut.eval();

    dut.clk = 0;
    dut.eval();

    printf("register rs1_data=%u rs2_data=%u\n", dut.rs1_data, dut.rs2_data);
    assert(dut.rs1_data == 42);
    assert(dut.rs2_data == 0);
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);

    Valu alu;
    test_alu(alu, 10, 15, 0, 25);
    test_alu(alu, 0xFF00, 0x00FF, 9, 0);

    Vdecoder decoder;
    // addi x1, x2, -1
    test_decoder(decoder, 0xFFF10093, 0x13, 0, 0x7F, 2, 0x1F, 1, (uint32_t)-1);
    // sub x3, x4, x5
    test_decoder(decoder, 0x405201B3, 0x33, 0, 0x20, 4, 5, 3, 0);

    Vregister reg;
    test_registers(reg);

    printf("All tests passed.\n");
    return 0;
}
