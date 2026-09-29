module uart #(
    parameter CLKS_PER_BIT = 434
) (
    input  wire       clk,
    input  wire       rst_n,

    input  wire [7:0] tx_data,
    input  wire       tx_start,
    output reg        tx_busy,
    output reg        tx,

    input  wire       rx,
    output wire [7:0] rx_data,
    output wire       rx_valid,
    input  wire       rx_read
);

    reg [$clog2(CLKS_PER_BIT)-1:0] clk_count;
    wire bit_done = (clk_count == CLKS_PER_BIT - 1);

    // idle  start  d0  d1  d2  d3  d4  d5  d6  d7  stop  idle
    //  1      0    ── data, LSB first ──────────    1     1

    localparam IDLE = 2'd0, START = 2'd1, DATA = 2'd2, STOP = 2'd3;
    reg [1:0] state;
    reg [7:0] shift_reg;
    reg [2:0] bit_index;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            tx        <= 1'b1;
            tx_busy   <= 1'b0;
            clk_count <= 0;
            shift_reg <= 8'd0;
            bit_index <= 3'd0;
        end else begin
            if (state == IDLE || bit_done)
                clk_count <= 0;
            else
                clk_count <= clk_count + 1;

            case (state)
                IDLE: if (tx_start) begin
                    shift_reg <= tx_data;
                    tx        <= 1'b0;
                    tx_busy   <= 1'b1;
                    state     <= START;
                end

                START: if (bit_done) begin
                    tx        <= shift_reg[0];  // d0
                    bit_index <= 3'd1;
                    state     <= DATA;
                end

                DATA: if (bit_done) begin
                    if (bit_index == 3'd0) begin
                        tx    <= 1'b1;
                        state <= STOP;
                    end else begin
                        tx        <= shift_reg[bit_index];
                        bit_index <= bit_index + 1;
                    end
                end

                STOP: if (bit_done) begin
                    tx_busy <= 1'b0;
                    state   <= IDLE;
                end
            endcase
        end
    end

    assign rx_data  = 8'd0;
    assign rx_valid = 1'b0;

endmodule
