module timer (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        rd_lo,
    input  wire        we,
    input  wire [1:0]  addr,
    input  wire [31:0] wdata,
    output reg  [31:0] rdata,
    output wire        mtip
);

    reg [63:0] count;
    reg [31:0] hi_latch;
    reg [63:0] mtimecmp;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count    <= 64'd0;
            hi_latch <= 32'd0;
            mtimecmp <= {64{1'b1}}; // never fires until software sets it
        end else begin
            count <= count + 64'd1;
            if (rd_lo)
                hi_latch <= count[63:32];
            if (we && addr == 2'd2)
                mtimecmp[31:0] <= wdata;
            if (we && addr == 2'd3)
                mtimecmp[63:32] <= wdata;
        end
    end

    always @(*) begin
        case (addr)
            2'd0: rdata = count[31:0];
            2'd1: rdata = hi_latch;
            2'd2: rdata = mtimecmp[31:0];
            2'd3: rdata = mtimecmp[63:32];
        endcase
    end

    assign mtip = (count >= mtimecmp);

endmodule
