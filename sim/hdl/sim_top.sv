// Simulation-only top level for sim/src/chip.rs: Marlin only sees ports, so
// this brings out the internal state the simulator needs.
//   uart_clks: clocks per UART bit (main's setting), so the sim's UART matches
//   halted:    ebreak is about to execute (main returned)
//   uart_busy: the UART is still sending a character
//   reg_idx/reg_val, ram_idx/ram_val: read a register or RAM word

module sim_top (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        uart_rx,
    input  wire        spi_miso,
    output wire        uart_tx,
    output wire        spi_cs_n,
    output wire        spi_sck,
    output wire        spi_mosi,
    output wire [31:0] pc,
    output wire [31:0] uart_clks,
    output wire        halted,
    output wire        uart_busy,
    input  wire [4:0]  reg_idx,
    output wire [31:0] reg_val,
    input  wire [12:0] ram_idx,
    output wire [31:0] ram_val
);
    main u_main (
        .clk(clk), .rst_n(rst_n), .pc_current_out(pc), .uart_tx(uart_tx), .uart_rx(uart_rx),
        .spi_cs_n(spi_cs_n), .spi_sck(spi_sck), .spi_mosi(spi_mosi), .spi_miso(spi_miso)
    );

    assign uart_clks = u_main.UART_CLKS_PER_BIT;
    assign halted    = u_main.state == 2'd1 && u_main.instr == 32'h00100073;   // EXEC, ebreak
    assign uart_busy = u_main.uart_tx_busy;
    assign reg_val   = u_main.u_register.registers[reg_idx];
    assign ram_val   = u_main.u_mem.memory[ram_idx];
endmodule
