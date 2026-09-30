// Simulation-only: rtl/uart.v at the bit lengths sim/tests/uart.rs uses
// (Marlin can't override parameters, so each gets a module).

`define UART_PORTS \
    input  wire       clk, \
    input  wire       rst_n, \
    input  wire [7:0] tx_data, \
    input  wire       tx_start, \
    output wire       tx_busy, \
    output wire       tx, \
    input  wire       rx, \
    output wire [7:0] rx_data, \
    output wire       rx_valid, \
    output wire       rx_overrun, \
    input  wire       rx_read, \
    input  wire       status_read

module uart_cpb4   (`UART_PORTS); uart #(.CLKS_PER_BIT(4))   u (.*); endmodule
module uart_cpb7   (`UART_PORTS); uart #(.CLKS_PER_BIT(7))   u (.*); endmodule
module uart_cpb2083 (`UART_PORTS); uart #(.CLKS_PER_BIT(2083)) u (.*); endmodule
