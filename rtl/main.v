module main (
    input wire clk,
    input wire rst_n
);

    wire [31:0] pc_next;
    wire [31:0] pc_current;

    pc u_pc (
        .clk(clk),
        .rst_n(rst_n),
        .pc_next(pc_next),
        .pc_current(pc_current)
    );

    wire [31:2] iram_idx;
    wire [31:0] iram_out;

    assign iram_idx = pc_current[31:2];
    assign pc_next  = pc_current + 32'd4;

    iram u_iram (
        .idx(iram_idx),
        .out(iram_out)
    );

    wire [31:0] inst;
    wire [6:0]  opcode;
    wire [2:0]  funct3;
    wire [6:0]  funct7;
    wire [4:0]  rs1;
    wire [4:0]  rs2;
    wire [4:0]  rd;
    wire [31:0] imm;

    assign inst = iram_out;

    decoder u_decoder (
        .inst(inst),
        .opcode(opcode),
        .funct3(funct3),
        .funct7(funct7),
        .rs1(rs1),
        .rs2(rs2),
        .rd(rd),
        .imm(imm)
    );

    wire [31:0] rs1_data, rs2_data;
    wire [31:0] rd_data;
    wire        reg_write_en;

    registe u_register (
        .clk(clk),
        .rst_n(rst_n),
        .rs1_addr(rs1),
        .rs2_addr(rs2),
        .rd_addr(rd),
        .rd_data(rd_data),
        .rd_write_en(reg_write_en),
        .rs1_data(rs1_data),
        .rs2_data(rs2_data)
    );

    wire [31:0] alu_in_b;
    assign alu_in_b = alu_src ? imm : rs2_data;

    wire [31:0] alu_result;
    wire        alu_zero;

    alu u_alu (
        .a(rs1_data),
        .b(alu_in_b),
        .alu_op(alu_op),
        .result(alu_result),
        .zero(alu_zero)
    );

    assign rd_data = alu_result;

endmodule
