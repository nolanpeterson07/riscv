module main (
    input wire clk,
    input wire rst_n,

    output wire [31:0] pc_current_out
);

    wire [31:0] pc_next;
    wire [31:0] pc_current;
    assign pc_current_out = pc_current;

    pc u_pc (
        .clk(clk),
        .rst_n(rst_n),
        .pc_next(pc_next),
        .pc_current(pc_current)
    );

    wire [31:2] iram_idx;
    wire [31:0] iram_out;

    assign iram_idx = pc_current[31:2];

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

    register u_register (
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

    wire [3:0] alu_op;
    wire       alu_src, mem_write, mem_to_reg, branch, jump;

    control_unit u_control (
        .opcode(opcode),
        .funct3(funct3),
        .funct7(funct7),
        .alu_op(alu_op),
        .alu_src(alu_src),
        .reg_write(reg_write_en),
        .mem_write(mem_write),
        .mem_to_reg(mem_to_reg),
        .branch(branch),
        .jump(jump)
    );

    wire [31:0] alu_in_a;
    assign alu_in_a = (opcode == 7'b0110111) ? 32'd0 :
                      (opcode == 7'b0010111) ? pc_current :
                      rs1_data;

    wire [31:0] alu_in_b;
    assign alu_in_b = alu_src ? imm : rs2_data;

    wire [31:0] alu_result;
    wire        alu_zero;

    alu u_alu (
        .operand_a(alu_in_a),
        .operand_b(alu_in_b),
        .op(alu_op),
        .result(alu_result),
        .zero(alu_zero)
    );

    wire [31:0] mem_data_out;

    mem u_mem (
        .clk      (clk),
        .addr     (alu_result),
        .data_in  (rs2_data),
        .mem_write(mem_write),
        .data_out (mem_data_out)
    );

    reg branch_taken;
    always @(*) begin
        case (funct3)
            3'b000:  branch_taken =  alu_zero;       // BEQ
            3'b001:  branch_taken = !alu_zero;       // BNE
            3'b100,
            3'b110:  branch_taken =  alu_result[0];  // BLT, BLTU
            3'b101,
            3'b111:  branch_taken = !alu_result[0];  // BGE, BGEU
            default: branch_taken = 1'b0;
        endcase
    end

    wire [31:0] pc_plus4;
    assign pc_plus4 = pc_current + 32'd4;

    assign pc_next = (opcode == 7'b1101111)    ? pc_current + imm :        // JAL
                     (opcode == 7'b1100111)    ? alu_result & ~32'd1 :     // JALR
                     (branch && branch_taken)  ? pc_current + imm :        // taken branch
                     pc_plus4;

    assign rd_data = jump       ? pc_plus4 :
                     mem_to_reg ? mem_data_out :
                     alu_result;

endmodule
