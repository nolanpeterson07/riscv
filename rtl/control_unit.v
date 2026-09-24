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
                endcase
            end
        endcase

    end

endmodule
