module muldiv(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,     // high through the whole instruction, drop after done
    input  wire [2:0]  funct3,
    input  wire [31:0] a,
    input  wire [31:0] b,
    output wire [31:0] result,
    output reg         done
);

    wire is_div = funct3[2];
    // signed operands: MULH a and b, MULHSU a, DIV/REM both
    wire sa = is_div ? !funct3[0] : (funct3[1:0] == 2'b01) || (funct3[1:0] == 2'b10);
    wire sb = is_div ? !funct3[0] : (funct3[1:0] == 2'b01);
    wire neg_a = sa & a[31];
    wire neg_b = sb & b[31];

    // multiply: {r, q} is the product, multiplier shifts out of q
    // divide: q is the quotient, dividend shifts out of q into r
    reg  [31:0] q, r, d;
    reg  [5:0]  cnt;
    reg         busy, neg_q, neg_r;

    wire [32:0] sum     = {1'b0, r} + (q[0] ? {1'b0, d} : 33'd0);
    wire [32:0] shifted = {r, q[31]};
    wire [32:0] diff    = shifted - {1'b0, d};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 1'b0;
            done <= 1'b0;
        end else if (!start) begin
            busy <= 1'b0;
            done <= 1'b0;
        end else if (!busy && !done) begin
            q     <= neg_a ? -a : a;
            d     <= neg_b ? -b : b;
            r     <= 32'd0;
            cnt   <= 6'd32;
            neg_q <= (neg_a ^ neg_b) && (b != 0);
            neg_r <= neg_a;                         // remainder takes the dividends sign
            busy  <= 1'b1;
        end else if (busy) begin
            if (is_div) begin
                r <= diff[32] ? shifted[31:0] : diff[31:0];
                q <= {q[30:0], !diff[32]};
            end else begin
                r <= sum[32:1];
                q <= {sum[0], q[31:1]};
            end
            cnt <= cnt - 6'd1;
            if (cnt == 6'd1) begin
                busy <= 1'b0;
                done <= 1'b1;
            end
        end
    end

    wire [63:0] prod = neg_q ? -{r, q} : {r, q};
    wire [31:0] quot = neg_q ? -q : q;
    wire [31:0] rem  = neg_r ? -r : r;

    assign result = !is_div ? (funct3[1:0] == 2'b00 ? prod[31:0] : prod[63:32]) :funct3[1] ? rem : quot;

endmodule
