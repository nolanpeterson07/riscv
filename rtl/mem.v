module mem (
    input  wire        clk,
    input  wire [31:0] addr,
    input  wire [31:0] data_in,
    input  wire        mem_write,
    input  wire [2:0]  funct3,     // access size and signedness
    output reg  [31:0] data_out
);

    reg [31:0] memory [0:1023];

    wire [9:0]  idx  = addr[11:2];   // 1024 words = 4 KiB
    wire [31:0] word = memory[idx];

    // stores
    always @(posedge clk) begin
        if (mem_write) begin
            case (funct3[1:0])
                2'b00: case (addr[1:0])
                    2'b00: memory[idx][7:0]   <= data_in[7:0];
                    2'b01: memory[idx][15:8]  <= data_in[7:0];
                    2'b10: memory[idx][23:16] <= data_in[7:0];
                    2'b11: memory[idx][31:24] <= data_in[7:0];
                endcase
                2'b01: if (addr[1])
                    memory[idx][31:16] <= data_in[15:0];
                else
                    memory[idx][15:0]  <= data_in[15:0];
                default: memory[idx] <= data_in;
            endcase
        end
    end

    // loads
    reg  [7:0]  byte_sel;
    always @(*) begin
        case (addr[1:0])
            2'b00: byte_sel = word[7:0];
            2'b01: byte_sel = word[15:8];
            2'b10: byte_sel = word[23:16];
            2'b11: byte_sel = word[31:24];
        endcase
    end
    wire [15:0] half_sel = addr[1] ? word[31:16] : word[15:0];

    always @(*) begin
        case (funct3)
            3'b000:  data_out = {{24{byte_sel[7]}}, byte_sel};   // LB
            3'b001:  data_out = {{16{half_sel[15]}}, half_sel};  // LH
            3'b100:  data_out = {24'd0, byte_sel};               // LBU
            3'b101:  data_out = {16'd0, half_sel};               // LHU
            default: data_out = word;                            // LW
        endcase
    end

endmodule
