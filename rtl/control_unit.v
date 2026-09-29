module control_unit(
    input wire  [6:0] opcode,
    input wire  [2:0] funct3,
    input wire  [6:0] funct7,

    output reg  [3:0] alu_op,
    output reg        alu_src,
    output reg        reg_write,
    output reg        mem_write,
    output reg        mem_to_reg,
    output reg        branch,
    output reg        jump
);

    localparam R_TYPE   = 7'b0110011;
    localparam I_ARITH  = 7'b0010011;
    localparam I_LOAD   = 7'b0000011;
    localparam I_JALR   = 7'b1100111;
    localparam S_TYPE   = 7'b0100011;
    localparam B_TYPE   = 7'b1100011;
    localparam U_LUI    = 7'b0110111;
    localparam U_AUIPC  = 7'b0010111;
    localparam J_JAL    = 7'b1101111;

    localparam ADD = 4'b0000;
    localparam SUB = 4'b0001;
    localparam SLL = 4'b0010;
    localparam SLT = 4'b0011;
    localparam SLTU = 4'b0100;
    localparam XOR = 4'b0101;
    localparam SRL = 4'b0110;
    localparam SRA = 4'b0111;
    localparam OR = 4'b1000;
    localparam AND = 4'b1001;

    always @(*) begin
        alu_op     = ADD;
        alu_src    = 0;
        reg_write  = 0;
        mem_write  = 0;
        mem_to_reg = 0;
        branch     = 0;
        jump       = 0;

        case (opcode)
            R_TYPE: begin
                alu_src    = 0;
                reg_write  = 1;
                mem_write  = 0;
                mem_to_reg = 0;
                branch     = 0;
                jump       = 0;

                case ({funct7, funct3})
                    10'b0000000_000: alu_op = ADD;
                    10'b0100000_000: alu_op = SUB;
                    10'b0000000_001: alu_op = SLL;
                    10'b0000000_010: alu_op = SLT;
                    10'b0000000_011: alu_op = SLTU;
                    10'b0000000_100: alu_op = XOR;
                    10'b0000000_101: alu_op = SRL;
                    10'b0100000_101: alu_op = SRA;
                    10'b0000000_110: alu_op = OR;
                    10'b0000000_111: alu_op = AND;
                    default: ;
                endcase
            end

            I_ARITH: begin
                alu_src    = 1;
                reg_write  = 1;
                mem_write  = 0;
                mem_to_reg = 0;
                branch     = 0;
                jump       = 0;

                case (funct3)
                    3'b000: alu_op = ADD;   // ADDI
                    3'b010: alu_op = SLT;   // SLTI
                    3'b011: alu_op = SLTU;  // SLTIU
                    3'b100: alu_op = XOR;   // XORI
                    3'b110: alu_op = OR;    // ORI
                    3'b111: alu_op = AND;   // ANDI
                    3'b001: alu_op = SLL;   // SLLI
                    3'b101: alu_op = funct7[5] ? SRA : SRL;  // SRLI vs SRAI, bit 30 selects
                endcase
            end

            I_LOAD: begin
                alu_src    = 1;
                reg_write  = 1;
                mem_write  = 0;
                mem_to_reg = 1;
                branch     = 0;
                jump       = 0;
                alu_op     = ADD; // All of these load values, all are add. No need for case
            end

            I_JALR: begin
                alu_src    = 1;
                reg_write  = 1;
                mem_write  = 0;
                mem_to_reg = 0;
                branch     = 0;
                jump       = 1;
                alu_op     = ADD;
            end

            S_TYPE: begin
                alu_src    = 1;
                reg_write  = 0;
                mem_write  = 1;
                mem_to_reg = 0;
                branch     = 0;
                jump       = 0;
                alu_op     = ADD;
            end

            B_TYPE: begin
                alu_src    = 0;
                reg_write  = 0;
                mem_write  = 0;
                mem_to_reg = 0;
                branch     = 1;
                jump       = 0;

                case (funct3)
                    3'b000: alu_op = SUB;   // BEQ
                    3'b001: alu_op = SUB;   // BNE
                    3'b100: alu_op = SLT;   // BLT
                    3'b101: alu_op = SLT;   // BGE
                    3'b110: alu_op = SLTU;  // BLTU
                    3'b111: alu_op = SLTU;  // BGEU
                    default: ;
                endcase
            end

            U_LUI: begin
                alu_src    = 1;
                reg_write  = 1;
                mem_write  = 0;
                mem_to_reg = 0;
                branch     = 0;
                jump       = 0;
                alu_op     = ADD;
            end

            U_AUIPC: begin
                alu_src    = 1;
                reg_write  = 1;
                mem_write  = 0;
                mem_to_reg = 0;
                branch     = 0;
                jump       = 0;
                alu_op     = ADD;
            end

            J_JAL: begin
                alu_src    = 0;    // dont care
                reg_write  = 1;
                mem_write  = 0;
                mem_to_reg = 0;
                branch     = 0;
                jump       = 1;
                alu_op     = ADD;  // dont care
            end
            default: ;
        endcase
    end

endmodule
