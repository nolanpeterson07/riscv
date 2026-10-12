use sim::chip::{self, Options};
use std::{path::Path, process::Command};

/// (program in fw/tests, mains return value, UART input, expected UART output)
const CASES: &[(&str, i32, &str, &str)] = &[
    ("array", 0, "", ""),
    ("math", 4965, "", ""),
    ("echo", 11, "hello riscv\n", "you said: HELLO RISCV"),
    ("echo", 2, "hi\r", "you said: HI"),
    (
        "libc",
        43,
        "",
        "-42 beef ok\r\nsorted: 10 20 30 40\r\nriscv32i len 8",
    ),
];

/// Builds a program with the Makefile
fn firmware(program: &str) -> Vec<u8> {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("..");
    let built = Command::new("make")
        .args(["-s", "fw", &format!("PROG={program}")])
        .current_dir(&root)
        .status();
    assert!(
        built.is_ok_and(|s| s.success()),
        "building {program} failed"
    );
    std::fs::read(root.join(format!("build/fw/{program}.bin"))).unwrap()
}

#[test]
fn programs() {
    let mut failures = vec![];
    for &(program, exit, uart_in, uart_out) in CASES {
        let opts = Options {
            max_cycles: 50_000_000,
            uart_in: uart_in.into(),
            ..Default::default()
        };
        let r = chip::run(firmware(program), &opts).unwrap();
        let out = String::from_utf8_lossy(&r.uart_out);
        if r.exit != Some(exit) || !out.contains(uart_out) || !r.flash_errors.is_empty() {
            failures.push(format!(
                "{program}: a0 = {:?}, uart {out:?}, flash errors {:?}",
                r.exit, r.flash_errors
            ));
        }
    }
    assert!(failures.is_empty(), "\n  {}", failures.join("\n  "));
}
