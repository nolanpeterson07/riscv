//! The real board: flashing programs onto it and talking to its uart
use std::{
    env,
    fs::{File, OpenOptions},
    io::{self, Read, Write},
    path::{Path, PathBuf},
    process::{exit, Command},
    sync::mpsc,
    thread,
};

/// openFPGALoader for the Tang Nano 9K: $LOADER if set, else the one in
/// ~/oss-cad-suite (or $OSS_CAD), else whatever is on PATH.
/// the board's USB chip (a BL702 pretending to be an FTDI) corrupts big JTAG
/// transfers at the default 6 MHz: CRC failures, then JTAG stuck until a replug
pub fn loader() -> Command {
    if let Ok(l) = env::var("LOADER") {
        let mut words = l.split_whitespace();
        let mut c = Command::new(words.next().unwrap_or("openFPGALoader"));
        c.args(words);
        return c;
    }
    let oss = env::var("OSS_CAD")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from(env::var("HOME").unwrap_or_default()).join("oss-cad-suite"));
    let local = oss.join("bin/openFPGALoader");
    let mut c = Command::new(if local.exists() { local } else { "openFPGALoader".into() });
    c.args(["-b", "tangnano9k", "--freq", "2000000"]);
    c
}

/// Puts a program in the external SPI flash the CPU boots from. The FPGA
/// resets afterwards, so the program starts right away
pub fn flash(bin: &Path) {
    if !loader().arg("--external-flash").arg(bin).status().is_ok_and(|s| s.success()) {
        eprintln!("flashing {} failed", bin.display());
        exit(1);
    }
}

/// Opens the board's uart: 9600 baud, raw.
/// configured with its own open and close first: setting it up on the open
/// file instead gets nothing but NULs once openFPGALoader has flashed
pub fn open(port: &str) -> File {
    let uart = OpenOptions::new()
        .read(true)
        .write(true)
        .open(port)
        .unwrap_or_else(|e| {
            eprintln!("can't open {port}: {e} (is the board plugged in? set PORT=...)");
            exit(1)
        });
    drop(uart);
    let configured = Command::new("stty")
        .args(["-F", port, "9600", "raw", "-echo"])
        .status()
        .is_ok_and(|s| s.success());
    if !configured {
        eprintln!("can't configure {port}");
        exit(1);
    }
    OpenOptions::new().read(true).write(true).open(port).unwrap()
}

/// Serial monitor: uart to stdout, keys to the uart, ctrl-c quits.
/// `first` runs once the uart is being read, e.g. flashing a program: what
/// the board sends while openFPGALoader is still running is lost otherwise
pub fn monitor(port: &str, first: impl FnOnce()) -> ! {
    let uart = open(port);
    let (tx_out, rx_out) = mpsc::channel();
    let mut rx = uart.try_clone().unwrap();
    thread::spawn(move || {
        let mut buf = [0; 256];
        while let Ok(n @ 1..) = rx.read(&mut buf) {
            if tx_out.send(buf[..n].to_vec()).is_err() {
                break;
            }
        }
    });
    first();

    // stdin unbuffered, so ctrl-c arrives as a byte instead of a signal
    Command::new("stty").args(["-icanon", "-echo", "-isig"]).status().ok();
    eprintln!("[monitor {port} @ 9600, ctrl-c to quit]");
    let mut tx = uart;
    thread::spawn(move || {
        for b in io::stdin().bytes().flatten() {
            if b == 3 {
                Command::new("stty").args(["icanon", "echo", "isig"]).status().ok();
                exit(0);
            }
            tx.write_all(&[b]).ok();
        }
    });
    let mut out = io::stdout();
    for chunk in rx_out {
        out.write_all(&chunk).ok();
        out.flush().ok();
    }
    exit(0)
}
