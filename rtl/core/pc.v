module pc (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          pc_write,
    input  wire [31:0]   pc_next,
    output reg  [31:0]   pc_current
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pc_current <= 32'd0;
        else if (pc_write)
            pc_current <= pc_next;
    end

endmodule
