use marlin::verilog::prelude::*;
use sim::{chip::runtime, flash::Flash};

#[verilog(src = "../rtl/spi_flash.v", name = "spi_flash")]
struct SpiFlash;

fn tick(dut: &mut SpiFlash, flash: &mut Flash) -> bool {
    let sck = dut.sck;
    for clk in [1, 0] {
        dut.clk = clk;
        dut.eval();
    }
    dut.miso = flash.step(dut.cs_n != 0, dut.sck != 0, dut.mosi != 0) as u8;
    dut.sck > sck
}

#[test]
fn reads_words_from_flash() {
    let rt = runtime(&["../rtl/spi_flash.v"]).unwrap();
    let mut dut: SpiFlash = rt.create_model_simple().unwrap();
    let image: Vec<u8> = (0..256u32).map(|i| (i * 37 + 11) as u8).collect();
    let mut flash = Flash::new(image.clone());

    // reset
    dut.eval();
    tick(&mut dut, &mut flash);
    dut.rst_n = 1;
    tick(&mut dut, &mut flash);

    // the flash starts asleep (like after openFPGALoader writes it), so the
    // controller has to wake it on its own before any read works
    assert!(flash.asleep);
    for _ in 0..2000 {
        tick(&mut dut, &mut flash);
    }
    assert_eq!(flash.wakes, 1, "sends the wake command once after reset");
    assert!(!flash.asleep);
    assert_eq!((dut.cs_n, dut.sck), (1, 0), "idle after waking");

    for addr in [0x00, 0x04, 0x10, 0xfc, 0x42, 0x13]
        .into_iter()
        .chain((0..64).map(|i| i * 4))
    {
        let a = addr as usize & !3;
        let expected = u32::from_le_bytes(image[a..a + 4].try_into().unwrap());
        let reads = flash.reads;

        dut.valid = 1;
        dut.addr = addr;
        let mut sck_rises = 0;
        while dut.ready == 0 {
            sck_rises += tick(&mut dut, &mut flash) as u32;
            assert!(sck_rises <= 64, "addr {addr:#x}: no ready");
        }
        assert_eq!(dut.rdata, expected, "addr {addr:#x}");
        tick(&mut dut, &mut flash);
        dut.valid = 0;
        assert_eq!(dut.ready, 0, "ready lasted more than one cycle");
        for _ in 0..4 {
            tick(&mut dut, &mut flash);
        }

        assert_eq!(sck_rises, 64, "a read is 64 sck cycles");
        assert_eq!(
            flash.reads,
            reads + 1,
            "read started more than once (restarted after ready?)"
        );
        assert_eq!(dut.cs_n, 1, "cs_n high after the read");
    }
    assert!(
        flash.errors.is_empty(),
        "protocol errors: {:?}",
        flash.errors
    );
}
