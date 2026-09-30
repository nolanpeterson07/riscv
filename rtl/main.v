module main #(
    parameter UART_CLKS_PER_BIT = 434
) (
    input wire clk,
    input wire rst_n,

    output wire [31:0] pc_current_out,
    output wire        uart_tx,
    input  wire        uart_rx
);

    // FETCH -> EXEC -> FETCH for most instructions
    // FETCH -> EXEC -> MEM -> FETCH for loads and stores
    localparam FETCH = 2'd0, EXEC = 2'd1, MEM = 2'd2;
    reg [1:0] state;
    reg [31:0] instr;
    wire [31:0] iram_out;

    wire alu_src, mem_write, mem_to_reg, branch, jump;
    wire is_mem = mem_write | mem_to_reg;
    wire finish = (state == EXEC && !is_mem) || (state == MEM);   // last cycle of the instruction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            instr <= 32'd0;
        else if (state == FETCH)
            instr <= iram_out;
    end

    wire [31:0] pc_next;
    wire [31:0] pc_current;
    assign pc_current_out = pc_current;

    pc u_pc (
        .clk(clk),
        .rst_n(rst_n),
        .pc_write(finish),
        .pc_next(pc_next),
        .pc_current(pc_current)
    );

    wire [31:2] iram_idx;

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

    assign inst = instr;

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
        .rd_write_en(reg_write_en && finish),
        .rs1_data(rs1_data),
        .rs2_data(rs2_data)
    );

    wire [3:0] alu_op;

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

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= FETCH;
        else case (state)
            FETCH:   state <= EXEC;
            EXEC:    state <= is_mem ? MEM : FETCH;
            default: state <= FETCH;
        endcase
    end

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

    // memory map
    //   0x0000_0000  RAM (4 KiB, up to 0x0000_0FFF; the rest of 0x0xxx_xxxx is unmapped)
    //   0x1000_0000  UART: +0 TX (write), +4 STATUS (read: bit0 tx_busy, bit1 rx_valid, bit2 rx_overrun), +8 RX (read)
    wire sel_ram  = (alu_result[31:12] == 20'h0);
    wire sel_uart = (alu_result[31:28] == 4'h1);

    mem u_mem (
        .clk      (clk),
        .addr     (alu_result),
        .data_in  (rs2_data),
        .mem_write(mem_write & sel_ram & state == MEM),
        .funct3   (funct3),
        .data_out (mem_data_out)
    );

    wire [3:0] uart_reg      = alu_result[3:0];
    wire       uart_tx_start = mem_write  & sel_uart & (uart_reg == 4'h0);
    wire       uart_rx_read  = mem_to_reg & sel_uart & (uart_reg == 4'h8) & state == MEM;
    wire       uart_tx_busy, uart_rx_valid, uart_rx_overrun;
    wire [7:0] uart_rx_data;

    uart #(.CLKS_PER_BIT(UART_CLKS_PER_BIT)) u_uart (
        .clk       (clk),
        .rst_n     (rst_n),
        .tx_data   (rs2_data[7:0]),
        .tx_start  (uart_tx_start & state == MEM),
        .tx_busy   (uart_tx_busy),
        .tx        (uart_tx),
        .rx        (uart_rx),
        .rx_data   (uart_rx_data),
        .rx_valid  (uart_rx_valid),
        .rx_overrun(uart_rx_overrun),
        .rx_read   (uart_rx_read)
    );

    wire [31:0] uart_rdata = (uart_reg == 4'h4) ? {29'd0, uart_rx_overrun, uart_rx_valid, uart_tx_busy} :
                             (uart_reg == 4'h8) ? {24'd0, uart_rx_data} :
                             32'd0;

    // unmapped addresses read as 0 and stores to them are dropped
    wire [31:0] load_data = sel_ram  ? mem_data_out :
                            sel_uart ? uart_rdata :
                            32'd0;

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
                     mem_to_reg ? load_data :
                     alu_result;

endmodule
