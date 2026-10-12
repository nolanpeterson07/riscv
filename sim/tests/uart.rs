use marlin::verilog::prelude::*;
use sim::chip::runtime;
use sim::uart::{Decoder, Encoder};

macro_rules! uart_test {
    ($test:ident, $module:literal, $Model:ident, $clks:expr) => {
        #[verilog(src = "hdl/uart_top.sv", name = $module)]
        struct $Model;

        #[test]
        fn $test() {
            const CLKS: u32 = $clks;
            fn tick(u: &mut $Model, n: u32) {
                for _ in 0..n {
                    for clk in [1, 0] {
                        u.clk = clk;
                        u.eval();
                    }
                }
            }
            fn wait_rx(u: &mut $Model, loopback: bool) -> bool {
                for _ in 0..20 * CLKS {
                    if u.rx_valid == 1 {
                        return true;
                    }
                    if loopback {
                        u.rx = u.tx;
                    }
                    tick(u, 1);
                }
                false
            }
            fn send(u: &mut $Model, byte: u8) {
                (u.tx_data, u.tx_start) = (byte, 1);
                tick(u, 1);
                u.tx_start = 0;
            }
            fn read_rx(u: &mut $Model) -> u8 {
                u.rx_read = 1;
                tick(u, 1);
                u.rx_read = 0;
                u.rx_data
            }

            let rt = runtime(&["../rtl/periph/uart.v", "hdl/uart_top.sv"]).unwrap();
            let u: &mut $Model = &mut rt.create_model_simple().unwrap();
            // reset
            (u.rst_n, u.rx) = (0, 1);
            u.eval();
            tick(u, 1);
            u.rst_n = 1;
            assert_eq!((u.tx, u.tx_busy), (1, 0), "idle after reset");

            // transmit
            for byte in [0x41, 0x00, 0xff, 0xa5, 0x55] {
                let mut dec = Decoder::new(CLKS);
                send(u, byte);
                let mut busy = 0;
                while u.tx_busy == 1 {
                    dec.step(u.tx != 0);
                    tick(u, 1);
                    busy += 1;
                    assert!(busy <= 11 * CLKS, "tx_busy stuck");
                }
                for _ in 0..CLKS {
                    dec.step(u.tx != 0);
                    tick(u, 1);
                }
                assert_eq!(dec.out, [byte]);
                assert_eq!(busy, 10 * CLKS, "busy should last one frame");
            }

            // receive every byte
            for byte in 0..=255u8 {
                // a byte arrives mid stop bit
                while u.tx_busy == 1 {
                    u.rx = u.tx;
                    tick(u, 1);
                }
                send(u, byte);
                assert!(wait_rx(u, true), "{byte:#04x} never arrived");
                assert_eq!(read_rx(u), byte);
                assert_eq!(u.rx_valid, 0, "reading RX should clear rx_valid");
            }

            // two bytes without reading
            let mut enc = Encoder::new(CLKS, vec![0x11, 0x22]);
            for _ in 0..24 * CLKS {
                u.rx = enc.step() as u8;
                tick(u, 1);
            }
            assert_eq!(u.rx_overrun, 1, "overrun not flagged");
            assert_eq!(read_rx(u), 0x22, "newest byte should be kept");
            assert_eq!(u.rx_overrun, 1, "reading RX should not clear overrun");
            u.status_read = 1;
            tick(u, 1);
            u.status_read = 0;
            assert_eq!(u.rx_overrun, 0, "reading STATUS should clear overrun");

            // a glitch
            u.rx = 0;
            tick(u, 1);
            u.rx = 1;
            assert!(!wait_rx(u, false), "a glitch produced a byte");
            for (byte, stop) in [(0x5a, 0), (0xc3, 1)] {
                let bits = [0]
                    .into_iter()
                    .chain((0..8).map(|i| byte >> i & 1))
                    .chain([stop, 1, 1]);
                for level in bits {
                    u.rx = level;
                    tick(u, CLKS);
                }
                assert_eq!(u.rx_valid, stop, "frame {byte:#04x} with stop bit {stop}");
            }
            assert_eq!(read_rx(u), 0xc3);
        }
    };
}

uart_test!(uart_4_clks_per_bit, "uart_cpb4", UartCpb4, 4);
uart_test!(uart_7_clks_per_bit, "uart_cpb7", UartCpb7, 7);
uart_test!(uart_2083_clks_per_bit, "uart_cpb2083", UartCpb2083, 2083); // 9600 baud at 20 MHz
