use sim::board;

/// Serial monitor: `monitor [port]`, 9600 baud, ctrl-c to quit
fn main() {
    let port = std::env::args().nth(1).unwrap_or_else(|| "/dev/ttyUSB1".into());
    board::monitor(&port, || {})
}
