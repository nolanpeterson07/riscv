// Read-only SPI flash controller on top of spi.v: one 32-bit word per read.
module flash #(
    parameter WAKE_CLKS = 1024   // wait after the wake command: ~38 us at 27 MHz, datasheets want a few us
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        valid,
    input  wire [23:0] addr,
    output reg         ready,
    output reg  [31:0] rdata,

    output reg         cs_n,
    output wire        sck,
    output wire        mosi,
    input  wire        miso
);

    // cs_n  ‾‾\____________________________________________/‾‾
    // mosi      [ 0x03 ][ addr (3 bytes) ][ don't care (4 bytes) ]
    // miso      [      ignored (4)       ][ data (4 bytes)       ]
    //
    // Before the first read, wake the chip: openFPGALoader leaves it in deep
    // power down after writing it, and then it ignores everything but 0xAB
    //   cs_n  ‾‾\________/‾‾‾‾ wait WAKE_CLKS ‾‾‾‾
    //   mosi     [ 0xAB ]

    localparam IDLE = 2'd0, BYTE = 2'd1, WAKE_WAIT = 2'd2;
    reg [1:0]  state;
    reg        awake;       // the wake command has been sent and waited out
    reg [31:0] out_shift;   // bytes still to send, next one on top
    reg [2:0]  byte_cnt;
    reg [2:0]  last_byte;   // 0 for the wake command, 7 for a read

    localparam WW = $clog2(WAKE_CLKS + 1);
    localparam [WW-1:0] WAKE_LAST = WAKE_CLKS - 1;
    reg [WW-1:0] wait_cnt;

    reg        spi_start;
    wire [7:0] spi_rx;
    wire       spi_done;

    spi u_spi (
        .clk   (clk),
        .rst_n (rst_n),
        .div   (16'd1),
        .start (spi_start),
        .tx    (out_shift[31:24]),
        .rx    (spi_rx),
        .busy  (),
        .done  (spi_done),
        .sck   (sck),
        .mosi  (mosi),
        .miso  (miso)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            awake     <= 1'b0;
            last_byte <= 3'd0;
            byte_cnt  <= 3'd0;
            wait_cnt  <= {WW{1'b0}};
            cs_n      <= 1'b1;
            spi_start <= 1'b0;
            ready     <= 1'b0;
            rdata     <= 32'd0;
            out_shift <= 32'd0;
        end else begin
            ready     <= 1'b0;
            spi_start <= 1'b0;

            case (state)
                IDLE: if (!awake) begin
                    out_shift <= {8'hAB, 24'd0};
                    last_byte <= 3'd0;
                    cs_n      <= 1'b0;
                    byte_cnt  <= 3'd0;
                    spi_start <= 1'b1;
                    state     <= BYTE;
                end else if (valid && !ready) begin
                    // command 0x03 then the word-aligned address
                    out_shift <= {8'h03, addr[23:2], 2'b00};
                    last_byte <= 3'd7;
                    cs_n      <= 1'b0;
                    byte_cnt  <= 3'd0;
                    spi_start <= 1'b1;
                    state     <= BYTE;
                end

                BYTE: if (spi_done) begin
                    out_shift <= {out_shift[23:0], 8'd0};
                    byte_cnt  <= byte_cnt + 1'b1;

                    // flash sends addr, addr+1, ... first: shift in from the top
                    if (byte_cnt[2])
                        rdata <= {spi_rx, rdata[31:8]};

                    if (byte_cnt == last_byte) begin
                        cs_n <= 1'b1;
                        if (!awake) begin
                            wait_cnt <= {WW{1'b0}};
                            state    <= WAKE_WAIT;
                        end else begin
                            ready <= 1'b1;
                            state <= IDLE;
                        end
                    end else begin
                        spi_start <= 1'b1;
                    end
                end

                WAKE_WAIT: begin
                    wait_cnt <= wait_cnt + 1'b1;
                    if (wait_cnt == WAKE_LAST) begin
                        awake <= 1'b1;
                        state <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
