use sim::chip::{self, Options};
use std::{path::Path, process::Command};

/// (program, mains return value, UART input, expected UART output)
const CASES: &[(&str, i32, &str, &str)] = &[
    ("tests/array.c", 0, "", ""),
    ("tests/math.c", 4965, "", ""),
    ("tests/echo.c", 11, "hello riscv\n", "you said: HELLO RISCV"),
];

/// Builds a program with the Makefile
fn firmware(program: &str) -> Vec<u8> {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("..");
    let built = Command::new("make")
        .args(["-s", "firmware", &format!("TEST={program}")])
        .current_dir(&root)
        .status();
    assert!(
        built.is_ok_and(|s| s.success()),
        "building {program} failed"
    );
    let name = Path::new(program).file_stem().unwrap().to_str().unwrap();
    std::fs::read(root.join(format!("build/{name}.bin"))).unwrap()
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
