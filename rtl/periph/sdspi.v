//   +0x0 DATA    write: send this byte (ignored while busy)
//                read:  byte received by the last transfer
//                (to receive, send 0xFF and read DATA afterwards)
//   +0x4 STATUS  bit0 busy (a transfer is in flight)
//   +0x8 CTRL    bit0 cs_n (reset 1 = deselected)
//   +0xC DIV     sck = clk / (2 * DIV); resets to INIT_DIV, SD init needs <= 400 kHz
module sdspi #(
    parameter INIT_DIV = 34   // 27 MHz / 68 = ~397 kHz
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        we,
    input  wire [1:0]  addr,      // bus_addr[3:2]
    input  wire [31:0] wdata,
    output reg  [31:0] rdata,

    output wire        cs_n,
    output wire        sck,
    output wire        mosi,
    input  wire        miso
);

    localparam DATA = 2'd0, STATUS = 2'd1, CTRL = 2'd2, DIVR = 2'd3;

    reg        cs_n_r;
    reg [15:0] div;
    assign cs_n = cs_n_r;

    wire       busy;
    wire [7:0] rx;
    wire       start = we && addr == DATA && !busy;

    spi u_spi (
        .clk   (clk),
        .rst_n (rst_n),
        .div   (div),
        .start (start),
        .tx    (wdata[7:0]),
        .rx    (rx),
        .busy  (busy),
        .done  (),
        .sck   (sck),
        .mosi  (mosi),
        .miso  (miso)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cs_n_r <= 1'b1;
            div    <= INIT_DIV;
        end else if (we) begin
            if (addr == CTRL) cs_n_r <= wdata[0];
            if (addr == DIVR) div    <= wdata[15:0];
        end
    end

    always @(*) begin
        case (addr)
            DATA:    rdata = {24'd0, rx};
            STATUS:  rdata = {31'd0, busy};
            CTRL:    rdata = {31'd0, cs_n_r};
            default: rdata = {16'd0, div};
        endcase
    end

endmodule
