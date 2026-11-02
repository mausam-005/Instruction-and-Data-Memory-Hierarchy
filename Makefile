# ==============================================================================
# Makefile: Instruction and Data Memory Hierarchy
# ==============================================================================

IVERILOG = iverilog
VVP      = vvp
GTKWAVE  = gtkwave
VIVADO   = vivado

# Directories
RTL_DIR   = rtl
SIM_DIR   = sim
SYNTH_DIR = synth
BENCH_DIR = benchmarks

.PHONY: all help sim-harvard sim-vn sim-comparison wave wave-vn wave-comp synth clean

all: sim-harvard

help:
	@echo "Available build and simulation targets:"
	@echo "  make sim-harvard     : Compile & simulate Harvard memory hierarchy"
	@echo "  make sim-vn          : Compile & simulate Von Neumann baseline"
	@echo "  make sim-comparison  : Run head-to-head comparison benchmark"
	@echo "  make wave            : Open Harvard simulation waveform in GTKWave"
	@echo "  make wave-vn         : Open Von Neumann simulation waveform in GTKWave"
	@echo "  make wave-comp       : Open comparison waveform in GTKWave"
	@echo "  make synth           : Run FPGA synthesis via Xilinx Vivado (batch mode)"
	@echo "  make clean           : Remove simulation build outputs and dumps"

sim-harvard:
	@mkdir -p $(SIM_DIR)
	$(IVERILOG) -g2012 -o $(SIM_DIR)/sim_harvard \
		$(RTL_DIR)/instruction_mem.v \
		$(RTL_DIR)/data_mem.v \
		$(RTL_DIR)/harvard_top.v \
		$(SIM_DIR)/tb_harvard_mem.v
	$(VVP) $(SIM_DIR)/sim_harvard

sim-vn:
	@mkdir -p $(SIM_DIR)
	$(IVERILOG) -g2012 -o $(SIM_DIR)/sim_vn \
		$(RTL_DIR)/mem_arbiter.v \
		$(RTL_DIR)/unified_mem.v \
		$(RTL_DIR)/von_neumann_top.v \
		$(SIM_DIR)/tb_von_neumann.v
	$(VVP) $(SIM_DIR)/sim_vn

sim-comparison:
	@mkdir -p $(SIM_DIR)
	$(IVERILOG) -g2012 -o $(SIM_DIR)/sim_comparison \
		$(RTL_DIR)/program_counter.v \
		$(RTL_DIR)/alu.v \
		$(RTL_DIR)/mini_core.v \
		$(RTL_DIR)/instruction_mem.v \
		$(RTL_DIR)/data_mem.v \
		$(RTL_DIR)/harvard_top.v \
		$(RTL_DIR)/mem_arbiter.v \
		$(RTL_DIR)/unified_mem.v \
		$(RTL_DIR)/von_neumann_top.v \
		$(SIM_DIR)/tb_comparison.v
	$(VVP) $(SIM_DIR)/sim_comparison

wave:
	$(GTKWAVE) $(SIM_DIR)/harvard_mem.vcd &

wave-vn:
	$(GTKWAVE) $(SIM_DIR)/von_neumann.vcd &

wave-comp:
	$(GTKWAVE) $(SIM_DIR)/comparison.vcd &

synth:
	$(VIVADO) -mode batch -source $(SYNTH_DIR)/run_synth.tcl

clean:
	rm -rf $(SIM_DIR)/sim_* $(SIM_DIR)/*.vcd $(SIM_DIR)/*.vvp
	rm -rf *.log *.jou .Xil synth/reports/
