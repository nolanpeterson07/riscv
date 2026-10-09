const CMD_READ: u8 = 0x03;
const CMD_WAKE: u8 = 0xab; // release from deep power-down
const SIZE: u32 = 1 << 24;
/// how long the chip needs after a wake before the next command (tRES1, a few
/// microseconds on the datasheets): 8 us at the sim's 20 MHz
const WAKE_CYCLES: u64 = 160;

pub struct Flash {
    image: Vec<u8>,
    prev_cs_n: bool,
    prev_sck: bool,
    bits: u32,
    header: u32,
    cmd: u8,
    miso: bool,
    /// in deep power-down: ignores everything but CMD_WAKE. Starts out true,
    /// because that's how openFPGALoader leaves the real chip after writing it
    pub asleep: bool,
    /// cycles since the last wake
    since_wake: u64,
    pub reads: u64,
    pub wakes: u64,
    pub errors: Vec<String>,
}

impl Flash {
    pub fn new(image: Vec<u8>) -> Flash {
        assert!(image.len() <= SIZE as usize, "image larger than the flash");
        Flash {
            image,
            prev_cs_n: true,
            prev_sck: false,
            bits: 0,
            header: 0,
            cmd: 0,
            miso: true,
            asleep: true,
            since_wake: u64::MAX,
            reads: 0,
            wakes: 0,
            errors: vec![],
        }
    }

    fn error(&mut self, msg: &str) {
        if self.errors.len() < 10 {
            self.errors.push(msg.into());
        }
    }

    pub fn step(&mut self, cs_n: bool, sck: bool, mosi: bool) -> bool {
        let (rose, fell) = (sck && !self.prev_sck, !sck && self.prev_sck);
        let reading = !self.asleep && self.bits >= 32 && self.cmd == CMD_READ;
        self.since_wake = self.since_wake.saturating_add(1);

        if cs_n {
            if !self.prev_cs_n {
                if reading {
                    self.reads += 1;
                }
                if self.bits >= 8 && self.cmd == CMD_WAKE {
                    self.asleep = false;
                    self.wakes += 1;
                    self.since_wake = 0;
                }
            }
            if self.prev_cs_n && (rose || fell) {
                self.error("sck toggled while cs_n was high");
            }
            self.bits = 0;
            self.miso = true;
        } else if self.prev_cs_n && sck {
            self.error("sck was high when cs_n fell (mode 0 idles low)");
        } else if self.prev_cs_n && self.since_wake < WAKE_CYCLES {
            let n = self.since_wake;
            self.error(&format!("cs_n fell {n} cycles after a wake, needs {WAKE_CYCLES}"));
        } else if rose {
            if self.bits < 32 {
                self.header = self.header << 1 | mosi as u32;
            }
            self.bits += 1;
            if self.bits == 8 {
                self.cmd = self.header as u8;
                let cmd = self.cmd;
                if self.asleep && cmd != CMD_WAKE {
                    self.error(&format!("command {cmd:#04x} in deep power-down (send 0xab first)"));
                } else if cmd != CMD_READ && cmd != CMD_WAKE {
                    self.error(&format!("unsupported command {cmd:#04x}"));
                }
            }
        } else if fell && reading {
            let n = self.bits - 32; // data bit number
            let addr = (self.header + n / 8) % SIZE;
            let byte = self.image.get(addr as usize).copied().unwrap_or(0xff); // erased flash reads 0xff
            self.miso = byte >> (7 - n % 8) & 1 != 0;
        }

        self.prev_cs_n = cs_n;
        self.prev_sck = sck;
        self.miso
    }
}
