#!/bin/bash
# ==============================================================================
# Simulation runner script: Instruction and Data Memory Hierarchy
# Usage: ./run.sh [harvard | pipe-harvard | vn | comp | core | icache | unified]
# ==============================================================================
set -e

MODE=${1:-pipe-harvard}
mkdir -p sim

if [ "$MODE" == "pipe-harvard" ] || [ "$MODE" == "harvard-pipe" ]; then
    echo "===> Compiling & Running Pipelined Harvard Subsystem Simulation (Role 4)..."
    iverilog -g2012 -o sim/sim_pipeline_harvard \
        rtl/pipe_regs.v \
        rtl/alu.v \
        rtl/hazard_unit.v \
        rtl/forwarding_unit.v \
        rtl/pipeline_core.v \
        rtl/instruction_mem.v \
        rtl/data_mem.v \
        sim/tb_pipeline_harvard.v
    vvp sim/sim_pipeline_harvard
elif [ "$MODE" == "unified" ] || [ "$MODE" == "pipe" ]; then
    echo "===> Compiling & Running Unified Von Neumann Pipelined Core Simulation..."
    iverilog -g2012 -o sim/sim_unified_pipe \
        rtl/pipe_regs.v \
        rtl/alu.v \
        rtl/hazard_unit.v \
        rtl/forwarding_unit.v \
        rtl/pipeline_core.v \
        rtl/unified_mem.v \
        rtl/phase2_telemetry.v \
        rtl/unified_pipeline_top.v \
        sim/tb_unified_pipeline.v
    vvp sim/sim_unified_pipe
elif [ "$MODE" == "vn" ]; then
    echo "===> Compiling & Running Von Neumann Baseline Simulation..."
    iverilog -g2012 -o sim/sim_vn \
        rtl/mem_arbiter.v \
        rtl/unified_mem.v \
        rtl/von_neumann_top.v \
        sim/tb_von_neumann.v
    vvp sim/sim_vn
elif [ "$MODE" == "core" ]; then
    echo "===> Compiling & Running RV32I Mini Core Datapath Unit Testbench..."
    iverilog -g2012 -o sim/sim_core \
        rtl/program_counter.v \
        rtl/alu.v \
        rtl/mini_core.v \
        sim/tb_mini_core.v
    vvp sim/sim_core
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
elif [ "$MODE" == "icache" ]; then
    echo "===> Compiling & Running L1 Instruction Cache Verification Testbench..."
    iverilog -g2012 -o sim/sim_icache \
        rtl/icache.v \
        sim/tb_icache.v
    vvp sim/sim_icache
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
