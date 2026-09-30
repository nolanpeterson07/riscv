pub struct Decoder {
    clks: u32,
    count: Option<u32>, // cycles since the start bit began
    bits: u8,
    pub out: Vec<u8>,
}

impl Decoder {
    pub fn new(clks: u32) -> Decoder {
        Decoder {
            clks,
            count: None,
            bits: 0,
            out: vec![],
        }
    }

    pub fn step(&mut self, tx: bool) {
        let Some(count) = self.count.map(|c| c + 1) else {
            if !tx {
                (self.count, self.bits) = (Some(0), 0);
            }
            return;
        };
        self.count = Some(count);
        if count % self.clks != self.clks / 2 {
            return; // not the middle of a bit
        }
        match count / self.clks {
            0 if tx => self.count = None, // start bit already over: a glitch
            n @ 1..=8 => self.bits |= (tx as u8) << (n - 1),
            9 => {
                if tx {
                    self.out.push(self.bits); // valid stop bit
                }
                self.count = None;
            }
            _ => {}
        }
    }
}

pub struct Encoder {
    clks: u64,
    input: Vec<u8>,
    cycle: u64,
}

impl Encoder {
    pub fn new(clks: u32, input: Vec<u8>) -> Encoder {
        Encoder {
            clks: clks as u64,
            input,
            cycle: 0,
        }
    }

    /// Level for rx this cycle
    pub fn step(&mut self) -> bool {
        let t = self.cycle.checked_sub(2 * self.clks);
        self.cycle += 1;
        let frame = 10 * self.clks;
        let Some(&byte) = t.and_then(|t| self.input.get((t / frame) as usize)) else {
            return true; // idle
        };
        match t.unwrap() % frame / self.clks {
            0 => false,                            // start bit
            n @ 1..=8 => byte >> (n - 1) & 1 != 0, // data, LSB first
            _ => true,                             // stop bit
        }
    }
}
