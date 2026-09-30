const CMD_READ: u8 = 0x03;
const SIZE: u32 = 1 << 24;

pub struct Flash {
    image: Vec<u8>,
    prev_cs_n: bool,
    prev_sck: bool,
    bits: u32,
    header: u32,
    miso: bool,
    pub reads: u64,
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
            miso: true,
            reads: 0,
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
        let reading = self.bits >= 32 && (self.header >> 24) as u8 == CMD_READ;

        if cs_n {
            if !self.prev_cs_n && reading {
                self.reads += 1;
            }
            if self.prev_cs_n && (rose || fell) {
                self.error("sck toggled while cs_n was high");
            }
            self.bits = 0;
            self.miso = true;
        } else if self.prev_cs_n && sck {
            self.error("sck was high when cs_n fell (mode 0 idles low)");
        } else if rose {
            if self.bits < 32 {
                self.header = self.header << 1 | mosi as u32;
            }
            self.bits += 1;
            if self.bits == 8 && self.header as u8 != CMD_READ {
                let cmd = self.header as u8;
                self.error(&format!("unsupported command {cmd:#04x}"));
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
