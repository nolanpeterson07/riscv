use std::{
    env,
    fs::{self, OpenOptions},
    io::{self, Read, Write},
    process::{exit, Command},
    thread,
};

fn sh(prog: &str, args: &[&str]) {
    if !Command::new(prog)
        .args(args)
        .status()
        .map_or(false, |s| s.success())
    {
        exit(1);
    }
}

fn make(target: &str, vars: &[String]) {
    let args: Vec<&str> = std::iter::once(target)
        .chain(vars.iter().map(String::as_str))
        .collect();
    sh("make", &args);
}

fn monitor(port: &str) {
    let rx = OpenOptions::new()
        .read(true)
        .write(true)
        .open(port)
        .expect("open port");
    let configured = Command::new("stty")
        .args(["9600", "raw", "-echo"])
        .stdin(rx.try_clone().expect("clone port"))
        .status()
        .map_or(false, |s| s.success());
    if !configured {
        exit(1);
    }
    sh("stty", &["-icanon", "-echo", "-isig"]); // stdin: unbuffered ctrl-c arrives as a byte
    eprintln!("[monitor {port} @ 9600, ctrl-c to quit]");
    let mut tx = rx.try_clone().expect("clone port");
    thread::spawn(move || {
        for b in io::stdin().bytes().flatten() {
            if b == 3 {
                Command::new("stty")
                    .args(["icanon", "echo", "isig"])
                    .status()
                    .ok();
                exit(0);
            }
            tx.write_all(&[b]).ok();
        }
    });
    io::copy(&mut &rx, &mut io::stdout()).ok();
}

fn default_port() -> String {
    let mut ports: Vec<String> = fs::read_dir("/dev")
        .map(|d| {
            d.flatten()
                .filter_map(|e| e.file_name().into_string().ok())
                .filter(|n| n.starts_with("cu.usbserial-"))
                .map(|n| format!("/dev/{n}"))
                .collect()
        })
        .unwrap_or_default();
    ports.sort();
    ports.pop().unwrap_or_else(|| "/dev/ttyUSB1".into())
}

fn main() {
    let (vars, cmds): (Vec<String>, Vec<String>) =
        env::args().skip(1).partition(|a| a.contains('='));
    let port = vars
        .iter()
        .find_map(|v| v.strip_prefix("PORT="))
        .map(String::from)
        .unwrap_or_else(default_port);
    let vars: Vec<String> = vars
        .into_iter()
        .filter(|v| !v.starts_with("PORT="))
        .collect();
    for c in &cmds {
        match c.as_str() {
            "build" => {
                make("fpga", &vars);
                make("firmware", &vars)
            }
            "flash" => make("fpga-flash", &vars),
            "load" => make("fpga-load", &vars),
            "monitor" => monitor(&port),
            _ => {
                eprintln!("usage: fpga <build|flash|load|monitor>... [TEST=file.c] [PORT=dev]");
                exit(1)
            }
        }
    }
}
