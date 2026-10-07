use crate::{flash::Flash, uart};
use marlin::verilator::tracing::{TraceFile, Waveform};
use marlin::verilator::{VerilatorRuntime, VerilatorRuntimeOptions};
use marlin::verilog::prelude::*;
use snafu::{ResultExt, Whatever};
use std::path::{Path, PathBuf};

pub const RAM_BASE: u32 = 0x0100_0000;

pub fn runtime(sources: &[impl AsRef<Path>]) -> Result<VerilatorRuntime, Whatever> {
    let dir = Path::new(env!("CARGO_MANIFEST_DIR"));
    let sources: Vec<PathBuf> = sources.iter().map(|s| dir.join(s)).collect();
    VerilatorRuntime::new2(
        dir.join("../build/marlin"),
        &sources,
        &[] as &[&Path],
        [],
        VerilatorRuntimeOptions::default(),
    )
}

pub struct Options {
    pub max_cycles: u64,
    pub uart_in: Vec<u8>,
    /// print the pc every cycle
    pub trace: bool,
    pub vcd: Option<PathBuf>,
}

impl Default for Options {
    fn default() -> Options {
        Options {
            max_cycles: 5_000_000,
            uart_in: vec![],
            trace: false,
            vcd: None,
        }
    }
}

pub struct RunResult {
    /// a0 when the program reached ebreak, None if it ran out of cycles
    pub exit: Option<i32>,
    pub pc: u32,
    pub cycles: u64,
    pub regs: [u32; 32],
    /// (address, value) of every nonzero RAM word
    pub ram: Vec<(u32, u32)>,
    pub uart_out: Vec<u8>,
    pub flash_reads: u64,
    pub flash_errors: Vec<String>,
}

#[verilog(src = "hdl/sim_top.sv", name = "sim_top")]
struct SimTop;

/// Runs `image` until ebreak or `opts.max_cycles`.
pub fn run(image: Vec<u8>, opts: &Options) -> Result<RunResult, Whatever> {
    let mut sources: Vec<PathBuf> =
        std::fs::read_dir(Path::new(env!("CARGO_MANIFEST_DIR")).join("../rtl"))
            .whatever_context("can't read rtl/")?
            .filter_map(|e| {
                Some(e.ok()?.path()).filter(|p| p.extension().is_some_and(|x| x == "v"))
            })
            .collect();
    sources.sort();
    sources.push("hdl/sim_top.sv".into());
    let rt = runtime(&sources)?;
    let config = VerilatedModelConfig::default()
        .verilator_optimization(3)
        .enable_tracing(opts.vcd.as_ref().map(|_| Waveform::Vcd));
    let mut chip: SimTop = rt
        .create_model(&config)
        .whatever_context("building the model failed")?;
    let mut vcd = opts.vcd.as_ref().map(|path| chip.open_trace(path));
    let mut time = 0;
    let mut flash = Flash::new(image);

    // one clock cycle
    fn tick(chip: &mut SimTop, flash: &mut Flash, vcd: &mut Option<TraceFile>, time: &mut u64) {
        for clk in [1, 0] {
            chip.clk = clk;
            chip.eval();
            if let Some(v) = vcd {
                v.dump(*time);
            }
            *time += 1;
        }
        chip.spi_miso = flash.step(chip.spi_cs_n != 0, chip.spi_sck != 0, chip.spi_mosi != 0) as u8;
    }

    // reset for one cycle
    (chip.uart_rx, chip.spi_miso, chip.rst_n) = (1, 1, 0);
    chip.eval();
    tick(&mut chip, &mut flash, &mut vcd, &mut time);
    chip.rst_n = 1;

    let mut uart_out = uart::Decoder::new(chip.uart_clks);
    let mut uart_in = uart::Encoder::new(chip.uart_clks, opts.uart_in.clone());
    let mut cycles = 0;
    while chip.halted == 0 && cycles < opts.max_cycles {
        chip.uart_rx = uart_in.step() as u8;
        tick(&mut chip, &mut flash, &mut vcd, &mut time);
        uart_out.step(chip.uart_tx != 0);
        cycles += 1;
        if opts.trace {
            println!("cycle {cycles:2} | pc_current = 0x{:08x}", chip.pc);
        }
    }

    let (halted, pc) = (chip.halted != 0, chip.pc);
    let regs: [u32; 32] = std::array::from_fn(|i| {
        chip.reg_idx = i as u8;
        chip.eval();
        chip.reg_val
    });
    let ram = (0..8192u16)
        .filter_map(|i| {
            chip.ram_idx = i;
            chip.eval();
            (chip.ram_val != 0).then(|| (RAM_BASE + 4 * i as u32, chip.ram_val))
        })
        .collect();

    // let the last character finish sending
    while chip.uart_busy != 0 {
        chip.uart_rx = 1;
        tick(&mut chip, &mut flash, &mut vcd, &mut time);
        uart_out.step(chip.uart_tx != 0);
    }

    Ok(RunResult {
        exit: halted.then_some(regs[10] as i32),
        pc,
        cycles,
        regs,
        ram,
        uart_out: uart_out.out,
        flash_reads: flash.reads,
        flash_errors: flash.errors,
    })
}
