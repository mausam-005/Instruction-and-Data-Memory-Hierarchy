#!/bin/bash
# ==============================================================================
# Simulation runner script: Instruction and Data Memory Hierarchy
# Usage: ./run.sh [harvard | vn | comp]
# ==============================================================================
set -e

MODE=${1:-harvard}
mkdir -p sim

if [ "$MODE" == "vn" ]; then
    echo "===> Compiling & Running Von Neumann Baseline Simulation..."
    iverilog -g2012 -o sim/sim_vn \
        rtl/mem_arbiter.v \
        rtl/unified_mem.v \
        rtl/von_neumann_top.v \
        sim/tb_von_neumann.v
    vvp sim/sim_vn
elif [ "$MODE" == "comp" ]; then
    echo "===> Compiling & Running Head-to-Head Comparative Benchmark..."
    iverilog -g2012 -o sim/sim_comparison \
        rtl/program_counter.v \
        rtl/alu.v \
        rtl/mini_core.v \
        rtl/instruction_mem.v \
        rtl/data_mem.v \
        rtl/harvard_top.v \
        rtl/mem_arbiter.v \
        rtl/unified_mem.v \
        rtl/von_neumann_top.v \
        sim/tb_comparison.v
    vvp sim/sim_comparison
else
    echo "===> Compiling & Running Harvard Memory Verification Testbench..."
    iverilog -g2012 -o sim/sim_harvard \
        rtl/instruction_mem.v \
        rtl/data_mem.v \
        rtl/harvard_top.v \
        sim/tb_harvard_mem.v
    vvp sim/sim_harvard
fi

echo "=================================================================="
echo " Simulation completed successfully!"
echo "=================================================================="
