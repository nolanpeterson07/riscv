RTL_SRCS = $(wildcard rtl/*.v)
MODULES  = $(basename $(notdir $(RTL_SRCS)))

CPP = sim/main.cpp

BUILD   = build
OBJ_DIR = $(BUILD)/obj_dir

VROOT = $(shell verilator --getenv VERILATOR_ROOT)
VINC  = $(VROOT)/include

MODEL_LIBS  = $(foreach m,$(MODULES),$(OBJ_DIR)/$(m)/V$(m)__ALL.a)
MODEL_INCS  = $(foreach m,$(MODULES),-I$(OBJ_DIR)/$(m))
RUNTIME_LIB = $(OBJ_DIR)/$(firstword $(MODULES))/libverilated.a

# Undefined weak symbols (sc_time_stamp, etc.) that verilator's own generated
# Makefiles allow via -U; needed here since we link by hand instead of --exe.
ifeq ($(shell uname),Darwin)
LDFLAGS = -Wl,-U,__Z15vl_time_stamp64v -Wl,-U,__Z13sc_time_stampv -Wl,-U,_vlog_startup_routines
endif

.PHONY: all sim wave clean

all: sim

sim: $(BUILD)/sim
	./$(BUILD)/sim

$(BUILD)/sim: $(CPP) $(MODEL_LIBS)
	c++ -Os -I$(VINC) -I$(VINC)/vltstd $(MODEL_INCS) $(CPP) $(MODEL_LIBS) $(RUNTIME_LIB) $(LDFLAGS) -pthread -o $(BUILD)/sim


define VERILATE_RULE
$$(OBJ_DIR)/$(1)/V$(1)__ALL.a: rtl/$(1).v | $$(OBJ_DIR)
	verilator -Wall -Wno-fatal --cc rtl/$(1).v --trace --Mdir $$(OBJ_DIR)/$(1) --top-module $(1)
	$$(MAKE) -C $$(OBJ_DIR)/$(1) -f V$(1).mk
endef
$(foreach m,$(MODULES),$(eval $(call VERILATE_RULE,$(m))))

$(OBJ_DIR):
	mkdir -p $(OBJ_DIR)

wave: sim
	gtkwave alu_verilator.vcd &

clean:
	rm -rf $(BUILD) *.vcd
