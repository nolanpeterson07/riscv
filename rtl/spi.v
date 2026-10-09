// SPI master, mode 0, one 8-bit transfer per start pulse, MSB first.
// Chip select is the caller's job, so a command can span many bytes.
// sck runs at clk / (2 * div); div >= 1, sampled every sck half period.
module spi (
    input  wire       clk,
    input  wire       rst_n,

    input  wire [15:0] div,

    input  wire       start,   // pulse while !busy
    input  wire [7:0] tx,
    output reg  [7:0] rx,      // valid when done pulses
    output reg        busy,
    output reg        done,    // one cycle

    output reg        sck,
    output reg        mosi,
    input  wire       miso
);

    reg [15:0]   div_cnt;
    reg [7:0]    out_shift;
    reg [2:0]    bit_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx        <= 8'd0;
            busy      <= 1'b0;
            done      <= 1'b0;
            sck       <= 1'b0;
            mosi      <= 1'b0;
            div_cnt   <= 16'd0;
            out_shift <= 8'd0;
            bit_cnt   <= 3'd0;
        end else begin
            done <= 1'b0;

            if (!busy) begin
                if (start) begin
                    mosi      <= tx[7];
                    out_shift <= {tx[6:0], 1'b0};
                    bit_cnt   <= 3'd0;
                    div_cnt   <= 16'd0;
                    busy      <= 1'b1;
                end
            end else if (div_cnt + 1'b1 < div) begin
                div_cnt <= div_cnt + 1'b1;
            end else begin
                div_cnt <= 16'd0;
                sck     <= ~sck;

                // sck falling: sample miso, present the next mosi bit
                if (sck) begin
                    rx        <= {rx[6:0], miso};
                    mosi      <= out_shift[7];
                    out_shift <= {out_shift[6:0], 1'b0};
                    bit_cnt   <= bit_cnt + 1'b1;
                    if (bit_cnt == 3'd7) begin
                        busy <= 1'b0;
                        done <= 1'b1;
                    end
                end
            end
        end
    end

endmodule
