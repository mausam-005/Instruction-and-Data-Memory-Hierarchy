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

.PHONY: all help sim-harvard sim-vn sim-core sim-comparison sim-icache sim-unified-pipe wave wave-vn wave-core wave-comp wave-unified synth synth-phase2 clean

all: sim-harvard

help:
	@echo "Available build and simulation targets:"
	@echo "  make sim-harvard      : Compile & simulate Harvard memory hierarchy"
	@echo "  make sim-vn           : Compile & simulate Von Neumann baseline"
	@echo "  make sim-core         : Compile & simulate RV32I execution engine datapath"
	@echo "  make sim-comparison   : Run head-to-head comparison benchmark"
	@echo "  make sim-icache       : Compile & simulate L1 Instruction Cache testbench"
	@echo "  make sim-unified-pipe : Compile & simulate Unified Von Neumann Pipelined Core"
	@echo "  make wave             : Open Harvard simulation waveform in GTKWave"
	@echo "  make wave-vn          : Open Von Neumann simulation waveform in GTKWave"
	@echo "  make wave-core        : Open Core unit simulation waveform in GTKWave"
	@echo "  make wave-comp        : Open comparison waveform in GTKWave"
	@echo "  make wave-unified     : Open Unified Pipelined Core waveform in GTKWave"
	@echo "  make synth            : Run Phase I FPGA synthesis via Xilinx Vivado (batch mode)"
	@echo "  make synth-phase2     : Run Phase II FPGA synthesis via Xilinx Vivado (batch mode)"
	@echo "  make clean            : Remove simulation build outputs and dumps"

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

sim-core:
	@mkdir -p $(SIM_DIR)
	$(IVERILOG) -g2012 -o $(SIM_DIR)/sim_core \
		$(RTL_DIR)/program_counter.v \
		$(RTL_DIR)/alu.v \
		$(RTL_DIR)/mini_core.v \
		$(SIM_DIR)/tb_mini_core.v
	$(VVP) $(SIM_DIR)/sim_core

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

sim-icache:
	@mkdir -p $(SIM_DIR)
	$(IVERILOG) -g2012 -o $(SIM_DIR)/sim_icache \
		$(RTL_DIR)/icache.v \
		$(SIM_DIR)/tb_icache.v
	$(VVP) $(SIM_DIR)/sim_icache

sim-unified-pipe:
	@mkdir -p $(SIM_DIR)
	$(IVERILOG) -g2012 -o $(SIM_DIR)/sim_unified_pipe \
		$(RTL_DIR)/pipe_regs.v \
		$(RTL_DIR)/alu.v \
		$(RTL_DIR)/pipeline_core.v \
		$(RTL_DIR)/unified_mem.v \
		$(RTL_DIR)/phase2_telemetry.v \
		$(RTL_DIR)/unified_pipeline_top.v \
		$(SIM_DIR)/tb_unified_pipeline.v
	$(VVP) $(SIM_DIR)/sim_unified_pipe

wave:
	$(GTKWAVE) $(SIM_DIR)/harvard_mem.vcd &

wave-vn:
	$(GTKWAVE) $(SIM_DIR)/von_neumann.vcd &

wave-core:
	$(GTKWAVE) $(SIM_DIR)/mini_core.vcd &

wave-comp:
	$(GTKWAVE) $(SIM_DIR)/comparison.vcd &

wave-unified:
	$(GTKWAVE) $(SIM_DIR)/unified_pipeline.vcd &

synth:
	$(VIVADO) -mode batch -source $(SYNTH_DIR)/run_synth.tcl

synth-phase2:
	$(VIVADO) -mode batch -source $(SYNTH_DIR)/run_phase2_synth.tcl

clean:
	rm -rf $(SIM_DIR)/sim_* $(SIM_DIR)/*.vcd $(SIM_DIR)/*.vvp
	rm -rf *.log *.jou .Xil synth/reports/
