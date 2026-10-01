module register (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [4:0]  rs1_addr,
    input  wire [4:0]  rs2_addr,
    input  wire [4:0]  rd_addr,
    input  wire [31:0] rd_data,
    input  wire        rd_write_en,
    output wire [31:0] rs1_data,
    output wire [31:0] rs2_data
);

    reg [31:0] registers [0:31];

    assign rs1_data = (rs1_addr == 5'd0) ? 32'd0 : registers[rs1_addr];
    assign rs2_data = (rs2_addr == 5'd0) ? 32'd0 : registers[rs2_addr];

    // No reset so synthesis can map this to distributed RAM on FPGA
    always @(posedge clk) begin
        if (rd_write_en && rd_addr != 5'd0)
            registers[rd_addr] <= rd_data;
    end

endmodule
