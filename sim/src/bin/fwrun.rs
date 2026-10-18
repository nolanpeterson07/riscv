use sim::{
    board,
    chip::{self, Options, RunResult},
};
use std::{
    env,
    io::{Read, Write},
    path::Path,
    process::{exit, Command, ExitCode},
    sync::{Arc, Mutex},
    thread,
    time::{Duration, Instant},
};

/// Cargo runner for fw/rust: `fwrun <elf>`, for both `cargo run` and
/// `cargo test`. Cargo puts test executables in .../deps/ and programs
/// (examples) elsewhere, which is how the two are told apart.
///
/// `cargo run --example name`: flashes the board and opens a serial monitor on
/// $PORT, like espflash. RV=sim runs it in the simulator instead.
///
/// `cargo test`: runs each test file in the simulator, or with RV=board on
/// the board, and turns its uart output (see fw/rust/src/lib.rs) into a
/// pass/fail exit code.
fn main() -> ExitCode {
    let Some(elf) = env::args().nth(1) else {
        eprintln!("usage: fwrun <elf>");
        return ExitCode::FAILURE;
    };
    let bin = Path::new(&elf).with_extension("bin");
    let objcopy = env::var("OBJCOPY").unwrap_or("riscv64-unknown-elf-objcopy".into());
    let copied = Command::new(&objcopy)
        .args(["-O", "binary", &elf])
        .arg(&bin)
        .status();
    if !copied.is_ok_and(|s| s.success()) {
        eprintln!("{objcopy} failed on {elf}");
        return ExitCode::FAILURE;
    }

    let name = Path::new(&elf).file_name().unwrap().to_string_lossy();
    let name = name.split('-').next().unwrap_or(&name);
    let is_test = Path::new(&elf)
        .parent()
        .and_then(|d| d.file_name())
        .is_some_and(|d| d == "deps");
    let target = env::var("RV").unwrap_or(if is_test { "sim" } else { "board" }.into());
    let port = env::var("PORT").unwrap_or("/dev/ttyUSB1".into());
    let out = match (is_test, target.as_str()) {
        (false, "sim") => {
            let r = sim(&bin);
            print!("{}", String::from_utf8_lossy(&r.uart_out));
            return ExitCode::from(r.exit.unwrap_or(1) as u8);
        }
        (false, "board") => board::monitor(&port, || board::flash(&bin)),
        (true, "sim") => {
            println!("\nrunning {name} on sim");
            String::from_utf8_lossy(&sim(&bin).uart_out).into()
        }
        (true, "board") => {
            println!("\nrunning {name} on board");
            board_test(&bin, &port)
        }
        _ => {
            eprintln!("RV must be sim or board");
            return ExitCode::FAILURE;
        }
    };
    if report(&out) {
        ExitCode::SUCCESS
    } else {
        ExitCode::FAILURE
    }
}

fn sim(bin: &Path) -> RunResult {
    let opts = Options {
        max_cycles: env::var("RV_CYCLES")
            .ok()
            .and_then(|c| c.parse().ok())
            .unwrap_or(50_000_000),
        uart_in: b"g".to_vec(),
        ..Default::default()
    };
    let image = std::fs::read(bin).unwrap();
    let r = chip::run(image, &opts).unwrap_or_else(|e| {
        eprintln!("simulator failed: {e:?}");
        exit(1)
    });
    if r.exit.is_none() {
        println!("no ebreak after {} cycles (pc = 0x{:08x})", r.cycles, r.pc);
    }
    r
}

fn board_test(bin: &Path, port: &str) -> String {
    let timeout = env::var("RV_TIMEOUT")
        .ok()
        .and_then(|t| t.parse().ok())
        .unwrap_or(30);
    let mut uart = board::open(port);

    // listen before flashing: the program starts as soon as the FPGA resets
    let got = Arc::new(Mutex::new(Vec::new()));
    let mut rx = uart.try_clone().unwrap();
    let sink = got.clone();
    thread::spawn(move || {
        let mut buf = [0; 256];
        while let Ok(n @ 1..) = rx.read(&mut buf) {
            sink.lock().unwrap().extend_from_slice(&buf[..n]);
        }
    });

    board::flash(bin);

    // the newest @READY is the new program and anything before it is old
    // output, so answer each new one in case an old one was still in flight
    let deadline = Instant::now() + Duration::from_secs(timeout);
    let text = || String::from_utf8_lossy(&got.lock().unwrap()).into_owned();
    let mut ready = None;
    while Instant::now() < deadline {
        let t = text();
        if let Some(i) = t.rfind("@READY") {
            if ready != Some(i) {
                uart.write_all(b"g").unwrap();
                ready = Some(i);
            }
            if t[i..].contains("@DONE") {
                break;
            }
        }
        thread::sleep(Duration::from_millis(50));
    }
    let t = text();
    match ready {
        Some(i) => {
            // let the rest of the @DONE line arrive
            thread::sleep(Duration::from_millis(100));
            text()[i..].into()
        }
        None => {
            println!("no @READY within {timeout} s, got {t:?}");
            String::new()
        }
    }
}

/// Prints results in cargo test's style; true if every test passed
fn report(out: &str) -> bool {
    let (mut current, mut passed, mut failed, mut done) = (None, 0, 0, false);
    for line in out.lines().map(|l| l.trim_end_matches('\r')) {
        if let Some(name) = line.strip_prefix("@T ") {
            current = Some(name.to_string());
        } else if line == "@OK" {
            println!("test {} ... ok", current.take().unwrap_or_default());
            passed += 1;
        } else if let Some(why) = line.strip_prefix("@FAIL ") {
            println!("test {} ... FAILED  {why}", current.take().unwrap_or_default());
            failed += 1;
        } else if line.starts_with("@DONE") {
            done = true;
            break;
        } else if line != "@READY" {
            println!("    | {line}");
        }
    }
    if let Some(name) = current {
        println!("test {name} ... no result (hung or timed out)");
        failed += 1;
    } else if !done {
        println!("no @DONE from the program");
        failed += 1;
    }
    let ok = failed == 0;
    println!(
        "test result: {}. {passed} passed; {failed} failed",
        if ok { "ok" } else { "FAILED" }
    );
    ok
}
