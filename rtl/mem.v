module mem (
    input  wire        clk,
    input  wire [31:0] addr,
    input  wire [31:0] data_in,
    input  wire        mem_write,
    output wire [31:0] data_out
);

    reg [31:0] memory [0:1023];

    always @(posedge clk) begin
        if (mem_write)
            memory[addr[31:2]] <= data_in;
    end

    assign data_out = memory[addr[31:2]];

endmodule
