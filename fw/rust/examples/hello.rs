#![no_std]
#![no_main]

use rvtest::println;

#[no_mangle]
extern "C" fn main() -> i32 {
    println!("hello world");
    0
}
