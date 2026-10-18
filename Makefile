BUILD = build

SIM_BIN  = $(BUILD)/cargo/release/sim
SIM_SRCS = sim/Cargo.toml $(wildcard sim/src/*.rs)

UART_IN  ?=
TRACE ?=
VCD   ?=

# --- RISC-V toolchain ---
RVCC  = riscv64-unknown-elf-gcc
RVOBJ = riscv64-unknown-elf-objcopy
RVFLAGS = -march=rv32im -mabi=ilp32
RVCFLAGS = $(RVFLAGS) -Ifw/include -Ifw/lib -Ifw/third_party/fatfs -O1 -fno-pic -fno-reorder-functions -ffunction-sections -fdata-sections
LINK_LD = fw/link.ld
RVLDFLAGS = --specs=nano.specs -nostartfiles -Wl,-m,elf32lriscv -Wl,--gc-sections -T $(LINK_LD)

# PROG=name picks fw/tests/name.c (or .s), else the Rust fw/rust/examples/name.rs
PROG ?=
CRT0 = fw/crt0.s
LIBC = $(wildcard fw/lib/*.c) fw/third_party/fatfs/ff.c

FW_SRC = $(firstword $(wildcard fw/tests/$(PROG).c fw/tests/$(PROG).s fw/rust/examples/$(PROG).rs))
FW_ELF = $(BUILD)/fw/$(PROG).elf
FW_BIN = $(BUILD)/fw/$(PROG).bin

ifeq ($(suffix $(FW_SRC)),.c)
FW_SRCS = $(CRT0) $(FW_SRC) $(LIBC)
else ifeq ($(suffix $(FW_SRC)),.rs)
FW_SRCS = $(FW_SRC) $(CRT0) $(wildcard fw/rust/src/*.rs)
else
FW_SRCS = $(FW_SRC)
endif

.PHONY: all fw sim test fpga load prog flash monitor wave clean

all: sim

sim: $(SIM_BIN) $(FW_BIN)
	$(SIM_BIN) $(FW_BIN) \
	    --uart-in "$(UART_IN)" \
	    $(if $(TRACE),--trace) $(if $(VCD),--vcd $(BUILD)/main.vcd)

$(SIM_BIN): $(SIM_SRCS)
	cd sim && cargo build --release --quiet
	@touch $@

test:
	cd sim && cargo test --release

fw: $(FW_BIN)

$(FW_ELF): $(FW_SRCS) $(LINK_LD)
	$(if $(FW_SRC),,$(error no fw/tests/$(PROG).c/.s or fw/rust/examples/$(PROG).rs, set PROG=name))
	@mkdir -p $(BUILD)/fw
ifeq ($(suffix $(FW_SRC)),.rs)
	cd fw/rust && cargo build --release --example $(PROG)
	cp $(BUILD)/rust/riscv32im-unknown-none-elf/release/examples/$(PROG) $@
else
	$(RVCC) $(RVCFLAGS) $(RVLDFLAGS) -o $@ $(FW_SRCS) -lc -lm -lgcc
endif

$(FW_BIN): $(FW_ELF)
	$(RVOBJ) -O binary $(FW_ELF) $(FW_BIN)

# --- Tang Nano 9K (OSS CAD Suite: yosys, nextpnr-himbaechel, gowin_pack, openFPGALoader) ---
FPGA_DEVICE = GW1NR-LV9QN88PC6/I5
FPGA_FAMILY = GW1N-9C
FPGA_SRCS   = $(shell find rtl -name '*.v') fpga/tangnano9k/top.v
FPGA_CST    = fpga/tangnano9k/tangnano9k.cst
FPGA_BIT    = $(BUILD)/fpga/top.fs

OSS_CAD ?= $(HOME)/oss-cad-suite
FPGA_TOOLS = $(if $(wildcard $(OSS_CAD)/bin/nextpnr-himbaechel),$(OSS_CAD)/bin/)

# the board's USB chip (a BL702 pretending to be an FTDI) corrupts big JTAG
# transfers at openFPGALoader's default 6 MHz: CRC failures, then JTAG stuck
# until a replug
LOADER = $(FPGA_TOOLS)openFPGALoader -b tangnano9k --freq 2000000

fpga: $(FPGA_BIT)

$(FPGA_BIT): $(FPGA_SRCS) $(FPGA_CST)
	@mkdir -p $(BUILD)/fpga
	$(FPGA_TOOLS)yosys -q -l $(BUILD)/fpga/yosys.log -p "read_verilog -sv $(FPGA_SRCS); synth_gowin -nodsp -top top -json $(BUILD)/fpga/top.json"
	$(FPGA_TOOLS)nextpnr-himbaechel --json $(BUILD)/fpga/top.json --write $(BUILD)/fpga/pnr.json --freq 27 \
	    --device $(FPGA_DEVICE) --vopt family=$(FPGA_FAMILY) --vopt cst=$(FPGA_CST)
	$(FPGA_TOOLS)gowin_pack -d $(FPGA_FAMILY) --mspi_as_gpio -o $@ $(BUILD)/fpga/pnr.json

# the program (PROG=...) goes in the external SPI flash the CPU fetches from.
# openFPGALoader resets the FPGA afterwards, which reboots the CPU from the
# FPGA's internal flash (put it there once with `make prog`)
flash: $(FW_BIN)
	$(LOADER) --external-flash $(FW_BIN)

# the CPU bitstream into FPGA SRAM, gone at power off
load: $(FPGA_BIT)
	$(LOADER) $(FPGA_BIT)

# the CPU bitstream into the FPGA's internal flash, loads itself at power on
prog: $(FPGA_BIT)
	$(LOADER) -f $(FPGA_BIT)

PORT ?= /dev/ttyUSB1

# serial monitor on the board's uart, ctrl-c to quit
monitor:
	cd sim && cargo run --release --quiet --bin monitor -- $(PORT)

wave:
	$(MAKE) sim VCD=1
	gtkwave $(BUILD)/main.vcd &

clean:
	rm -rf $(BUILD) *.vcd
