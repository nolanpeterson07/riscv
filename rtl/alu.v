module alu (
    input reg [31:0] operand_a,
    input reg [31:0] operand_b,
    input reg [3:0] op,
    output reg [31:0] result,
    output wire zero
);

    localparam ADD = 4'b0000;

    always @(*) begin
        case(op)
            ADD: result = operand_a + operand_b;
            default: result = 32'd0;
        endcase
    end

    assign zero = (result == 32'd0);

endmodule
