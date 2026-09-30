BUILD = build

SIM_BIN  = $(BUILD)/cargo/release/sim
SIM_SRCS = sim/Cargo.toml $(wildcard sim/src/*.rs)

UART_IN  ?=
TRACE ?=
VCD   ?=

# --- RISC-V toolchain ---
RVCC  = riscv64-unknown-elf-gcc
RVOBJ = riscv64-unknown-elf-objcopy
RVFLAGS = -march=rv32i -mabi=ilp32
RVCFLAGS = $(RVFLAGS) -Isim -O1 -ffreestanding -nostdlib -fno-pic -fno-reorder-functions \
           -fno-tree-loop-distribute-patterns  # keep gcc from turning memset/memcpy loops into calls to themselves
LINK_LD = sim/link.ld
RVLDFLAGS = -nostdlib -Wl,-m,elf32lriscv -T $(LINK_LD)

TEST ?= test.s
CRT0 = sim/crt0.s
LIBC = sim/lib.c

FW_NAME = $(basename $(notdir $(TEST)))
FW_ELF  = $(BUILD)/$(FW_NAME).elf
FW_BIN  = $(BUILD)/$(FW_NAME).bin

ifeq ($(suffix $(TEST)),.c)
FW_SRCS = $(CRT0) $(TEST) $(LIBC)
else
FW_SRCS = $(TEST)
endif
CYCLES ?= 5000000

.PHONY: all sim test wave clean firmware fpga fpga-load fpga-flash

all: sim

sim: $(SIM_BIN) $(FW_BIN)
	$(SIM_BIN) $(FW_BIN) --cycles $(CYCLES) \
	    --uart-in "$(UART_IN)" \
	    $(if $(TRACE),--trace) $(if $(VCD),--vcd $(BUILD)/main.vcd)

$(SIM_BIN): $(SIM_SRCS)
	cd sim && cargo build --release --quiet
	@touch $@

test:
	cd sim && cargo test --release

firmware: $(FW_BIN)

$(FW_ELF): $(FW_SRCS) $(LINK_LD) | $(BUILD)
	$(RVCC) $(RVCFLAGS) $(RVLDFLAGS) -o $@ $(FW_SRCS) -lgcc

$(FW_BIN): $(FW_ELF)
	$(RVOBJ) -O binary $(FW_ELF) $(FW_BIN)

$(BUILD):
	mkdir -p $(BUILD)

# --- Tang Nano 9K (OSS CAD Suite: yosys, nextpnr-himbaechel, gowin_pack, openFPGALoader) ---
FPGA_DEVICE = GW1NR-LV9QN88PC6/I5
FPGA_FAMILY = GW1N-9C
FPGA_SRCS   = $(wildcard rtl/*.v) fpga/top.v
FPGA_CST    = fpga/tangnano9k.cst
FPGA_BIT    = $(BUILD)/fpga/top.fs

fpga: $(FPGA_BIT)

$(FPGA_BIT): $(FPGA_SRCS) $(FPGA_CST)
	@mkdir -p $(BUILD)/fpga
	yosys -q -l $(BUILD)/fpga/yosys.log -p "read_verilog -sv $(FPGA_SRCS); synth_gowin -top top -json $(BUILD)/fpga/top.json"
	nextpnr-himbaechel --json $(BUILD)/fpga/top.json --write $(BUILD)/fpga/pnr.json --freq 27 \
	    --device $(FPGA_DEVICE) --vopt family=$(FPGA_FAMILY) --vopt cst=$(FPGA_CST)
	gowin_pack -d $(FPGA_FAMILY) -o $@ $(BUILD)/fpga/pnr.json

fpga-flash: $(FW_BIN)
	openFPGALoader -b tangnano9k --external-flash $(FW_BIN)

fpga-load: $(FPGA_BIT)
	openFPGALoader -b tangnano9k $(FPGA_BIT)

wave:
	$(MAKE) sim VCD=1
	gtkwave $(BUILD)/main.vcd &

clean:
	rm -rf $(BUILD) *.vcd
