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
RVAS  = riscv64-unknown-elf-as
RVLD  = riscv64-unknown-elf-ld
RVOBJ = riscv64-unknown-elf-objcopy
RVFLAGS = -march=rv32i -mabi=ilp32

FW_SRC = test.s
FW_ELF = $(BUILD)/test.elf
FW_BIN = $(BUILD)/test.bin
FW_HEX = firmware.hex

.PHONY: all sim wave clean compile_commands.json firmware

all: sim compile_commands.json

sim: $(BUILD)/sim $(FW_HEX)
	./$(BUILD)/sim

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

# --- firmware build: .s -> .elf -> .bin -> firmware.hex ---
firmware: $(FW_HEX)

$(FW_HEX): $(FW_SRC) | $(BUILD)
	$(RVAS) $(RVFLAGS) -o $(BUILD)/test.o $(FW_SRC)
	$(RVLD) -m elf32lriscv -Ttext=0x0 -o $(FW_ELF) $(BUILD)/test.o
	$(RVOBJ) -O binary $(FW_ELF) $(FW_BIN)
	xxd -e -g4 -c4 $(FW_BIN) | awk '{print $$2}' > $(FW_HEX)

$(BUILD):
	mkdir -p $(BUILD)

wave: sim
	gtkwave $(BUILD)/main.vcd &

clean:
	rm -rf $(BUILD) *.vcd $(FW_HEX)
