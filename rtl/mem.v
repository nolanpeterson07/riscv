module mem (
    input  wire        clk,
    input  wire [31:0] addr,
    input  wire [31:0] wdata,
    input  wire [3:0]  wstrb,      // which bytes to write
    output wire [31:0] data_out
);

    reg [31:0] memory [0:1023];

    // TODO: need to change for real chip
    initial begin
        $readmemh("firmware.hex", memory);
    end

    wire [9:0]  idx  = addr[11:2];   // 1024 words = 4 KiB

    always @(posedge clk) begin
        if (wstrb[0]) memory[idx][7:0]   <= wdata[7:0];
        if (wstrb[1]) memory[idx][15:8]  <= wdata[15:8];
        if (wstrb[2]) memory[idx][23:16] <= wdata[23:16];
        if (wstrb[3]) memory[idx][31:24] <= wdata[31:24];
    end

    // reads: always the whole word
    assign data_out = memory[idx];

endmodule
