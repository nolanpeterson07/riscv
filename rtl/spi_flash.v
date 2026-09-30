module spi_flash (
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

    localparam IDLE = 1'b0, SHIFT = 1'b1;
    reg        state;
    reg [30:0] out_shift;   // command + address still to send, MSB first
    reg [30:0] in_shift;    // bits seen on miso so far
    reg [5:0]  bit_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
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
                IDLE: if (valid && !ready) begin
                    // command 0x03 then the word-aligned address: 32 bits, MSB first
                    mosi      <= 1'b0;
                    out_shift <= {7'h03, addr[23:2], 2'b00};
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

                        if (bit_cnt == 6'd63) begin
                            cs_n  <= 1'b1;
                            // flash sends addr, addr+1, ... first, reverse
                            rdata <= {in_shift[6:0], miso, in_shift[14:7], in_shift[22:15], in_shift[30:23]};
                            ready <= 1'b1;
                            state <= IDLE;
                        end
                    end
                end
            endcase
        end
    end

endmodule
