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
    output reg  [7:0] rx_data, // TODO: make a bigger buffer
    output reg        rx_valid,
    output reg        rx_overrun,
    input  wire       rx_read,
    input  wire       status_read
);

    // counter compare values, sized to match the counters
    localparam CW = $clog2(CLKS_PER_BIT);
    localparam integer  LAST_I   = CLKS_PER_BIT - 1;
    localparam integer  HALF_I   = (CLKS_PER_BIT - 1) / 2;
    localparam [CW-1:0] LAST_CLK = LAST_I[CW-1:0];   // last cycle of a bit
    localparam [CW-1:0] HALF_CLK = HALF_I[CW-1:0];   // middle of a bit

    reg [CW-1:0] clk_count;
    wire bit_done = (clk_count == LAST_CLK);

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

    // rx comes from outside the chip, not in step with clk so passed through 2 flip flops
    reg rx_meta, rx_sync;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
        end else begin
            rx_meta <= rx;
            rx_sync <= rx_meta;
        end
    end

    reg [1:0] rx_state;
    reg [CW-1:0] rx_count;
    reg [7:0] rx_shift;
    reg [2:0] rx_bit;

    wire rx_half_done = (rx_count == HALF_CLK);
    wire rx_bit_done  = (rx_count == LAST_CLK);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_state   <= IDLE;
            rx_count   <= 0;
            rx_shift   <= 8'd0;
            rx_bit     <= 3'd0;
            rx_data    <= 8'd0;
            rx_valid   <= 1'b0;
            rx_overrun <= 1'b0;
        end else begin
            if (rx_state == IDLE || (rx_state == START ? rx_half_done : rx_bit_done))
                rx_count <= 0;
            else
                rx_count <= rx_count + 1;

            // the CPU read the byte
            if (rx_read)
                rx_valid <= 1'b0;

            if (status_read)
                rx_overrun <= 1'b0;

            case (rx_state)
                IDLE: if (!rx_sync)
                    rx_state <= START;

                START: if (rx_half_done) begin
                    if (!rx_sync) begin             // still low in the middle, real start bit
                        rx_bit   <= 3'd0;
                        rx_state <= DATA;
                    end else begin                  // glitch
                        rx_state <= IDLE;
                    end
                end

                DATA: if (rx_bit_done) begin
                    rx_shift <= {rx_sync, rx_shift[7:1]};   // LSB arrives first
                    rx_bit   <= rx_bit + 1;
                    if (rx_bit == 3'd7)
                        rx_state <= STOP;
                end

                STOP: if (rx_bit_done) begin
                    if (rx_sync) begin
                        rx_data  <= rx_shift;
                        rx_valid <= 1'b1;
                        if (rx_valid && !rx_read)
                            rx_overrun <= 1'b1;
                    end                             // framing error
                    rx_state <= IDLE;
                end
            endcase
        end
    end

endmodule
