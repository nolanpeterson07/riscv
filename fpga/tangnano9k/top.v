module top (
    input  wire       clk,         // 27 MHz
    input  wire       btn_rst_n,   // S1, low when pressed
    input  wire       uart_rx,
    output wire       uart_tx,
    output wire       flash_cs_n,
    output wire       flash_sck,
    output wire       flash_mosi,
    input  wire       flash_miso,
    output wire       sd_cs_n,
    output wire       sd_sck,
    output wire       sd_mosi,
    input  wire       sd_miso,
    output wire [5:0] led
);

    // The FPGA doesnt pulse reset at power up, so hold the CPU in reset for a
    // few ms after configuration and while S1 is pressed
    // rst_n comes straight from a flop: it drives every async clear, and
    // nextpnr times clear->Q, so logic in front of it lands on the critical path
    reg [1:0]  btn_sync  = 2'b00;
    reg [17:0] por_count = 18'd0;
    reg        rst_n     = 1'b0;

    always @(posedge clk) begin
        btn_sync <= {btn_sync[0], btn_rst_n};
        if (!btn_sync[1]) begin
            por_count <= 18'd0;
            rst_n     <= 1'b0;
        end else if (!rst_n) begin
            por_count <= por_count + 18'd1;
            rst_n     <= &por_count;
        end
    end

    main #(
        .UART_CLKS_PER_BIT(2813)   // 27 MHz / 9600 baud
    ) u_main (
        .clk           (clk),
        .rst_n         (rst_n),
        .pc_current_out(),
        .uart_tx       (uart_tx),
        .uart_rx       (uart_rx),
        .spi_cs_n      (flash_cs_n),
        .spi_sck       (flash_sck),
        .spi_mosi      (flash_mosi),
        .spi_miso      (flash_miso),
        .sd_cs_n       (sd_cs_n),
        .sd_sck        (sd_sck),
        .sd_mosi       (sd_mosi),
        .sd_miso       (sd_miso)
    );

    assign led = {3'b111, flash_cs_n, uart_tx, ~rst_n};

endmodule
