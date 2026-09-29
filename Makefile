RTL_SRCS = $(wildcard rtl/*.v)

CPP = sim/main.cpp

BUILD   = build
OBJ_DIR = $(BUILD)/obj_dir

VROOT = $(shell verilator --getenv VERILATOR_ROOT)
VINC  = $(VROOT)/include

TOP = main

MAIN_LIB    = $(OBJ_DIR)/$(TOP)/V$(TOP)__ALL.a
RUNTIME_LIB = $(OBJ_DIR)/$(TOP)/libverilated.a

ifeq ($(shell uname),Darwin)
LDFLAGS = -Wl,-U,__Z15vl_time_stamp64v -Wl,-U,__Z13sc_time_stampv -Wl,-U,_vlog_startup_routines
endif

CXXFLAGS = -Os -I$(VINC) -I$(VINC)/vltstd -I$(OBJ_DIR)/$(TOP)

# --- RISC-V toolchain ---
RVCC  = riscv64-unknown-elf-gcc
RVOBJ = riscv64-unknown-elf-objcopy
RVFLAGS = -march=rv32i -mabi=ilp32
RVCFLAGS = $(RVFLAGS) -O1 -ffreestanding -nostdlib -fno-pic -fno-reorder-functions \
           -fno-tree-loop-distribute-patterns  # keep gcc from turning memset/memcpy loops into calls to themselves
RVLDFLAGS = -nostdlib -Wl,-m,elf32lriscv -Wl,-Ttext=0x0 -Wl,-N -Wl,--no-warn-rwx-segments  # -N: place data right after code, no page alignment

TEST ?= test.s
CRT0 = sim/crt0.s
LIBC = sim/lib.c

FW_NAME = $(basename $(notdir $(TEST)))
FW_ELF  = $(BUILD)/$(FW_NAME).elf
FW_BIN  = $(BUILD)/$(FW_NAME).bin
FW_HEX  = firmware.hex

ifeq ($(suffix $(TEST)),.c)
FW_SRCS = $(CRT0) $(TEST) $(LIBC)
CYCLES ?= 10000
else
FW_SRCS = $(TEST)
CYCLES ?= 20
endif

.PHONY: all sim wave clean compile_commands.json firmware $(FW_HEX)

all: sim compile_commands.json

sim: $(BUILD)/sim $(FW_HEX)
	./$(BUILD)/sim $(CYCLES)

$(BUILD)/sim: $(CPP) $(MAIN_LIB)
	c++ $(CXXFLAGS) $(CPP) $(MAIN_LIB) $(RUNTIME_LIB) $(LDFLAGS) -pthread -o $(BUILD)/sim

compile_commands.json: $(MAIN_LIB)
	@jq -n --arg dir "$(CURDIR)" --arg file "$(CURDIR)/$(CPP)" \
	  --arg args "c++ $(CXXFLAGS) $(CPP) $(LDFLAGS) -pthread -o $(BUILD)/sim" \
	  '[{directory: $$dir, file: $$file, arguments: ($$args | split(" "))}]' > $@

$(MAIN_LIB): $(RTL_SRCS) | $(OBJ_DIR)
	verilator -Wall -Wno-fatal --cc $(RTL_SRCS) --trace --Mdir $(OBJ_DIR)/$(TOP) --top-module $(TOP) --public
	$(MAKE) -C $(OBJ_DIR)/$(TOP) -f V$(TOP).mk

$(OBJ_DIR):
	mkdir -p $(OBJ_DIR)

# --- firmware build: .s/.c -> .elf -> .bin -> firmware.hex ---
# firmware.hex is phony so switching TEST always rebuilds it
firmware: $(FW_HEX)

$(FW_ELF): $(FW_SRCS) | $(BUILD)
	$(RVCC) $(RVCFLAGS) $(RVLDFLAGS) -o $@ $(FW_SRCS) -lgcc

$(FW_HEX): $(FW_ELF)
	$(RVOBJ) -O binary -j .text -j .rodata -j .srodata -j .data -j .sdata $(FW_ELF) $(FW_BIN)
	xxd -e -g4 -c4 $(FW_BIN) | awk '{print $$2}' > $(FW_HEX)

$(BUILD):
	mkdir -p $(BUILD)

wave: sim
	gtkwave $(BUILD)/main.vcd &

clean:
	rm -rf $(BUILD) *.vcd $(FW_HEX)
