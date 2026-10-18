module timer (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        rd_lo,
    input  wire        addr,
    output wire [31:0] rdata
);

    reg [63:0] count;
    reg [31:0] hi_latch;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count    <= 64'd0;
            hi_latch <= 32'd0;
        end else begin
            count <= count + 64'd1;
            if (rd_lo)
                hi_latch <= count[63:32];
        end
    end

    assign rdata = addr ? hi_latch : count[31:0];

endmodule
