#![no_std]

use core::fmt::{self, Write};
use core::ptr::{read_volatile, write_volatile};

core::arch::global_asm!(include_str!("../../crt0.s"));

const UART_TX: *mut u32 = 0x1000_0000 as _;
const UART_STATUS: *const u32 = 0x1000_0004 as _;
const UART_RX: *const u32 = 0x1000_0008 as _;
const TX_BUSY: u32 = 1 << 0;
const RX_VALID: u32 = 1 << 1;

pub fn putc(c: u8) {
    unsafe {
        while read_volatile(UART_STATUS) & TX_BUSY != 0 {}
        write_volatile(UART_TX, c as u32);
    }
}

pub fn getc() -> u8 {
    unsafe {
        while read_volatile(UART_STATUS) & RX_VALID == 0 {}
        read_volatile(UART_RX) as u8
    }
}

pub struct Uart;

impl Write for Uart {
    fn write_str(&mut self, s: &str) -> fmt::Result {
        for b in s.bytes() {
            if b == b'\n' {
                putc(b'\r');
            }
            putc(b);
        }
        Ok(())
    }
}

#[macro_export]
macro_rules! println {
    ($($arg:tt)*) => {{
        use core::fmt::Write;
        let _ = writeln!($crate::Uart, $($arg)*);
    }};
}

/// a0 = code, then ebreak
#[no_mangle]
pub extern "C" fn exit(code: i32) -> ! {
    unsafe { core::arch::asm!("ebreak", in("a0") code) };
    loop {}
}

#[panic_handler]
fn panic(info: &core::panic::PanicInfo) -> ! {
    match info.location() {
        Some(l) => println!("Panic {}:{} {}", l.file(), l.line(), info.message()),
        None => println!("Panic: {}", info.message()),
    }

    exit(1)
}
