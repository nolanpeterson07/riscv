use std::{
    env,
    fs::OpenOptions,
    io::{self, Read, Write},
    process::{exit, Command},
    thread,
};

fn stty(args: &[&str]) -> Command {
    let mut c = Command::new("stty");
    c.args(args);
    c
}

/// Serial monitor: `monitor <port>`, 9600 baud, ctrl-c to quit
fn main() {
    let port = env::args().nth(1).unwrap_or_else(|| "/dev/ttyUSB1".into());
    let rx = OpenOptions::new()
        .read(true)
        .write(true)
        .open(&port)
        .unwrap_or_else(|e| {
            eprintln!("can't open {port}: {e}");
            exit(1)
        });
    let configured = stty(&["9600", "raw", "-echo"])
        .stdin(rx.try_clone().expect("clone port"))
        .status()
        .map_or(false, |s| s.success());
    if !configured {
        exit(1);
    }
    // stdin: unbuffered, ctrl-c arrives as a byte
    stty(&["-icanon", "-echo", "-isig"]).status().ok();
    eprintln!("[monitor {port} @ 9600, ctrl-c to quit]");
    let mut tx = rx.try_clone().expect("clone port");
    thread::spawn(move || {
        for b in io::stdin().bytes().flatten() {
            if b == 3 {
                stty(&["icanon", "echo", "isig"]).status().ok();
                exit(0);
            }
            tx.write_all(&[b]).ok();
        }
    });
    io::copy(&mut &rx, &mut io::stdout()).ok();
}
