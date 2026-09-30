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

.PHONY: all sim test wave clean firmware

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

wave:
	$(MAKE) sim VCD=1
	gtkwave $(BUILD)/main.vcd &

clean:
	rm -rf $(BUILD) *.vcd
