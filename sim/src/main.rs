use sim::chip::{self, Options};
use std::process::ExitCode;

const USAGE: &str =
    "usage: sim <firmware.bin> [--cycles N] [--uart-in TEXT] [--trace] [--vcd FILE]";

fn parse_args() -> Result<(String, Options), String> {
    fn num<T: std::str::FromStr>(flag: &str, v: Option<String>) -> Result<T, String> {
        v.and_then(|v| v.parse().ok())
            .ok_or(format!("{flag} needs a number"))
    }
    let mut args = std::env::args().skip(1);
    let (mut file, mut opts) = (None, Options::default());
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--cycles" => opts.max_cycles = num(&arg, args.next())?,
            "--uart-in" => {
                let text = args.next().ok_or("--uart-in needs text")?;
                opts.uart_in = text
                    .replace("\\n", "\n")
                    .replace("\\r", "\r")
                    .replace("\\t", "\t")
                    .into_bytes();
            }
            "--vcd" => opts.vcd = Some(args.next().ok_or("--vcd needs a file")?.into()),
            "--trace" => opts.trace = true,
            _ if arg.starts_with('-') => return Err(USAGE.into()),
            _ => file = Some(arg),
        }
    }
    Ok((file.ok_or(USAGE)?, opts))
}

fn main() -> ExitCode {
    let result = parse_args().and_then(|(file, opts)| {
        let image = std::fs::read(&file).map_err(|e| format!("can't read {file}: {e}"))?;
        chip::run(image, &opts).map_err(|e| format!("{e:?}"))
    });
    let r = match result {
        Ok(r) => r,
        Err(e) => {
            eprintln!("{e}");
            return ExitCode::FAILURE;
        }
    };

    match r.exit {
        Some(a0) => println!("ebreak at pc = 0x{:08x}, a0 = {a0}", r.pc),
        None => println!("no ebreak after {} cycles (pc = 0x{:08x})", r.cycles, r.pc),
    }
    println!("cycles: {}, flash reads: {}", r.cycles, r.flash_reads);
    for (i, v) in r.regs.iter().enumerate() {
        println!("x{i:<2} = 0x{v:08x}");
    }
    for (addr, v) in &r.ram {
        println!("ram 0x{addr:08x}: 0x{v:08x}");
    }
    for e in &r.flash_errors {
        println!("spi flash error: {e}");
    }
    if !r.uart_out.is_empty() {
        println!("--- uart ---\n{}", String::from_utf8_lossy(&r.uart_out));
    }
    ExitCode::SUCCESS
}
