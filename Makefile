RTL = rtl/alu.v
CPP = sim/main.cpp
TOP = alu

BUILD = build

.PHONY: all verilator wave clean

all: verilator

verilator: $(BUILD)/obj_dir/V$(TOP)
	./$(BUILD)/obj_dir/V$(TOP)

$(BUILD)/obj_dir/V$(TOP): $(RTL) $(CPP) | $(BUILD)
	verilator -Wall --cc $(RTL) --exe --build $(CURDIR)/$(CPP) --trace \
		-o V$(TOP) --Mdir $(BUILD)/obj_dir

wave: verilator
	gtkwave $(TOP)_verilator.vcd &

$(BUILD):
	mkdir -p $(BUILD)

clean:
	rm -rf $(BUILD) *.vcd
