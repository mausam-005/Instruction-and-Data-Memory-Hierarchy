# ==============================================================================
# Script: run_synth.tcl
# Tool: Xilinx Vivado (Batch Mode)
# Usage: vivado -mode batch -source synth/run_synth.tcl
# ==============================================================================

set project_name "memory_hierarchy_synth"
set part_name "xc7a35tcpg236-1" ;# Artix-7 (Basys 3 / standard academic FPGA)
set output_dir "./synth/reports"

file mkdir $output_dir

# ------------------------------------------------------------------------------
# 1. Harvard Architecture FPGA Synthesis (Top: harvard_top)
# ------------------------------------------------------------------------------
puts "===> [1/2] Adding Harvard Verilog RTL source files..."
read_verilog -sv ./rtl/instruction_mem.v
read_verilog -sv ./rtl/data_mem.v
read_verilog -sv ./rtl/harvard_top.v

puts "===> Setting up 100 MHz target clock constraint for Harvard..."
create_clock -period 10.000 -name clk [get_ports clk]

puts "===> Running Synthesis on top-level module: harvard_top..."
synth_design -top harvard_top -part $part_name -mode out_of_context

puts "===> Generating Harvard Synthesis Reports to $output_dir..."
report_utilization -file "$output_dir/utilization_harvard.rpt"
report_timing_summary -file "$output_dir/timing_harvard.rpt"
report_power -file "$output_dir/power_harvard.rpt"

# ------------------------------------------------------------------------------
# 2. Von Neumann Architecture FPGA Synthesis (Top: von_neumann_top)
# ------------------------------------------------------------------------------
puts "===> [2/2] Adding Von Neumann Verilog RTL source files..."
close_design
read_verilog -sv ./rtl/mem_arbiter.v
read_verilog -sv ./rtl/unified_mem.v
read_verilog -sv ./rtl/von_neumann_top.v

puts "===> Setting up 100 MHz target clock constraint for Von Neumann..."
create_clock -period 10.000 -name clk [get_ports clk]

puts "===> Running Synthesis on top-level module: von_neumann_top..."
synth_design -top von_neumann_top -part $part_name -mode out_of_context

puts "===> Generating Von Neumann Synthesis Reports to $output_dir..."
report_utilization -file "$output_dir/utilization_von_neumann.rpt"
report_timing_summary -file "$output_dir/timing_von_neumann.rpt"
report_power -file "$output_dir/power_von_neumann.rpt"

puts "===> Dual-Architecture FPGA Synthesis Completed Successfully!"
exit
