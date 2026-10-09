module spi_flash #(
    parameter WAKE_CLKS = 1024   // wait after the wake command: ~38 us at 27 MHz, datasheets want a few us
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        valid,
    input  wire [23:0] addr,
    output reg         ready,
    output reg  [31:0] rdata,

    output reg         cs_n,
    output reg         sck,
    output reg         mosi,
    input  wire        miso
);

    // cs_n  ‾‾\____________________________________________/‾‾
    // mosi      [ 0x03 ][     address (24)    ][ don't care ]
    // miso      [        ignored (32)         ][ data (32)  ]
    // mode 0: mosi changes while sck is low, both sides sample on sck rising edge

    // Before the first read, wake the chip: openFPGALoader leaves it in deep
    // power down after writing it, and then it ignores everything but 0xAB
    //   cs_n  ‾‾\________/‾‾‾‾ wait WAKE_CLKS ‾‾‾‾
    //   mosi     [ 0xAB ]

    localparam IDLE = 2'd0, SHIFT = 2'd1, WAKE_WAIT = 2'd2;
    reg [1:0]  state;
    reg        awake;       // the wake command has been sent and waited out
    reg [30:0] out_shift;   // command + address still to send, MSB first
    reg [30:0] in_shift;    // bits seen on miso so far
    reg [5:0]  bit_cnt;
    reg [5:0]  last_bit;    // bit_cnt of the last bit: 7 for the wake command, 63 for a read

    localparam WW = $clog2(WAKE_CLKS + 1);
    localparam [WW-1:0] WAKE_LAST = WAKE_CLKS - 1;
    reg [WW-1:0] wait_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            awake     <= 1'b0;
            last_bit  <= 6'd0;
            wait_cnt  <= {WW{1'b0}};
            cs_n      <= 1'b1;
            sck       <= 1'b0;
            mosi      <= 1'b0;
            ready     <= 1'b0;
            rdata     <= 32'd0;
            out_shift <= 31'd0;
            in_shift  <= 31'd0;
            bit_cnt   <= 6'd0;
        end else begin
            ready <= 1'b0;

            case (state)
                IDLE: if (!awake) begin
                    // 0xAB = 1010_1011: first bit out now, the other 7 from out_shift
                    mosi      <= 1'b1;
                    out_shift <= {7'b010_1011, 24'd0};
                    last_bit  <= 6'd7;
                    cs_n      <= 1'b0;
                    bit_cnt   <= 6'd0;
                    state     <= SHIFT;
                end else if (valid && !ready) begin
                    // command 0x03 then the word-aligned address: 32 bits, MSB first
                    mosi      <= 1'b0;
                    out_shift <= {7'h03, addr[23:2], 2'b00};
                    last_bit  <= 6'd63;
                    cs_n      <= 1'b0;
                    bit_cnt   <= 6'd0;
                    state     <= SHIFT;
                end

                SHIFT: begin
                    sck <= ~sck;

                    if (sck) begin
                        in_shift  <= {in_shift[29:0], miso};
                        out_shift <= {out_shift[29:0], 1'b0};
                        mosi      <= out_shift[30];
                        bit_cnt   <= bit_cnt + 1;

                        if (bit_cnt == last_bit) begin
                            cs_n <= 1'b1;
                            if (!awake) begin
                                wait_cnt <= {WW{1'b0}};
                                state    <= WAKE_WAIT;
                            end else begin
                                // flash sends addr, addr+1, ... first, reverse
                                rdata <= {in_shift[6:0], miso, in_shift[14:7], in_shift[22:15], in_shift[30:23]};
                                ready <= 1'b1;
                                state <= IDLE;
                            end
                        end
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
