# ==============================================================================
# Script: run_phase2_synth.tcl
# Project: Instruction and Data Memory Hierarchy (Phase II)
# Author : Daniel Tayal (2401010140)
# Tool   : AMD / Xilinx Vivado (Batch Mode)
# Target : Xilinx Artix-7 FPGA (xc7a35tcpg236-1)
# Usage  : vivado -mode batch -source synth/run_phase2_synth.tcl
# ==============================================================================

set project_name "phase2_hierarchy_synth"
set part_name "xc7a35tcpg236-1" ;# AMD/Xilinx Artix-7 (Basys 3 / Nexys A7 FPGA)
set output_dir "./synth/reports"

file mkdir $output_dir

puts "=============================================================================="
puts "  STARTING PHASE II FPGA BATCH SYNTHESIS: ARTIX-7 (xc7a35tcpg236-1)           "
puts "  Author: Daniel Tayal (2401010140)                                           "
puts "=============================================================================="

# ------------------------------------------------------------------------------
# 1. Unified Von Neumann Pipelined Core Synthesis (Top: unified_pipeline_top)
# ------------------------------------------------------------------------------
puts ""
puts "===> [1/3] Adding Unified Von Neumann Pipelined RTL source files..."
read_verilog -sv ./rtl/pipe_regs.v
read_verilog -sv ./rtl/alu.v
read_verilog -sv ./rtl/pipeline_core.v
read_verilog -sv ./rtl/unified_mem.v
read_verilog -sv ./rtl/phase2_telemetry.v
read_verilog -sv ./rtl/unified_pipeline_top.v

puts "===> Applying 100 MHz clock constraint (Period = 10.000 ns)..."
create_clock -period 10.000 -name clk [get_ports clk]

puts "===> Running Synthesis on top-level module: unified_pipeline_top..."
synth_design -top unified_pipeline_top -part $part_name -mode out_of_context

puts "===> Generating Unified Pipelined Core Synthesis Reports to $output_dir..."
report_utilization -file "$output_dir/utilization_unified_pipeline.rpt"
report_timing_summary -file "$output_dir/timing_unified_pipeline.rpt"
report_power -file "$output_dir/power_unified_pipeline.rpt"

# ------------------------------------------------------------------------------
# 2. Pipelined Harvard Subsystem Synthesis (Top: pipeline_harvard_top)
# ------------------------------------------------------------------------------
puts ""
puts "===> [2/3] Adding Pipelined Harvard RTL source files..."
close_design
read_verilog -sv ./rtl/icache.v
read_verilog -sv ./rtl/pipeline_harvard_top.v

puts "===> Applying 100 MHz clock constraint (Period = 10.000 ns)..."
create_clock -period 10.000 -name clk [get_ports clk]

puts "===> Running Synthesis on top-level module: pipeline_harvard_top..."
synth_design -top pipeline_harvard_top -part $part_name -mode out_of_context

puts "===> Generating Pipelined Harvard Synthesis Reports to $output_dir..."
report_utilization -file "$output_dir/utilization_pipeline_harvard.rpt"
report_timing_summary -file "$output_dir/timing_pipeline_harvard.rpt"
report_power -file "$output_dir/power_pipeline_harvard.rpt"

# ------------------------------------------------------------------------------
# 3. 32-Bit Hardware Performance Telemetry Engine Synthesis (Top: phase2_telemetry)
# ------------------------------------------------------------------------------
puts ""
puts "===> [3/3] Adding Phase 2 Hardware Telemetry Engine RTL source files..."
close_design
read_verilog -sv ./rtl/phase2_telemetry.v

puts "===> Applying 100 MHz clock constraint (Period = 10.000 ns)..."
create_clock -period 10.000 -name clk [get_ports clk]

puts "===> Running Synthesis on standalone module: phase2_telemetry..."
synth_design -top phase2_telemetry -part $part_name -mode out_of_context

puts "===> Generating Telemetry Engine Synthesis Reports to $output_dir..."
report_utilization -file "$output_dir/utilization_telemetry.rpt"
report_timing_summary -file "$output_dir/timing_telemetry.rpt"
report_power -file "$output_dir/power_telemetry.rpt"

puts ""
puts "=============================================================================="
puts "  PHASE II FPGA BATCH SYNTHESIS COMPLETED SUCCESSFULLY!                       "
puts "  All reports written to: $output_dir                                         "
puts "=============================================================================="
exit
