module decoder (
    input wire [31:0] inst,

    output wire [6:0]  opcode,
    output wire [2:0]  funct3,
    output wire [6:0]  funct7,
    output wire [4:0]  rs1,
    output wire [4:0]  rs2,
    output wire [4:0]  rd,
    output wire [31:0] imm,
    output wire [11:0] csr_addr,
    output wire [4:0]  zimm
);

    assign opcode = inst[6:0];
    assign rd = inst[11:7];
    assign funct3 = inst[14:12];
    assign rs1 = inst[19:15];
    assign rs2 = inst[24:20];
    assign funct7 = inst[31:25];
    assign csr_addr = inst[31:20];
    assign zimm = inst[19:15];

    localparam R_TYPE   = 7'b0110011; // default case; everything above already sets it
    localparam I_ARITH  = 7'b0010011;
    localparam I_LOAD   = 7'b0000011;
    localparam I_JALR   = 7'b1100111;
    localparam S_TYPE   = 7'b0100011;
    localparam B_TYPE   = 7'b1100011;
    localparam U_LUI    = 7'b0110111;
    localparam U_AUIPC  = 7'b0010111;
    localparam J_JAL    = 7'b1101111;

    reg [31:0] imm_r;
    assign imm = imm_r;

    always @(*) begin
        case(opcode)
            I_ARITH, I_LOAD, I_JALR:
                imm_r = {{20{inst[31]}}, inst[31:20]};

            S_TYPE:
                imm_r = {{20{inst[31]}}, inst[31:25], inst[11:7]};

            B_TYPE:
                imm_r = {{19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0};

            U_LUI, U_AUIPC:
                imm_r = {inst[31:12], 12'b0};

            J_JAL:
                imm_r = {{11{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0};

            default:
                imm_r = 32'd0;
        endcase
    end

endmodule
