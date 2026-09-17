module iram (
    input  wire [31:2] idx,
    output reg  [31:0] out
);
    reg [31:0] mem [0:1023];

    initial begin
        $readmemh("firmware.hex", mem);
    end

    always @(*) begin
        out = mem[idx];
    end

endmodule
