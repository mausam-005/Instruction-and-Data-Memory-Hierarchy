// =============================================================================
// Project: Instruction and Data Memory Hierarchy (Phase II)
// Module : unified_pipeline_top.v
// Author : Daniel Tayal (2401010140)
// Description:
//   Unified Von Neumann Pipelined Baseline Core Subsystem.
//   Integrates the 5-Stage RV32I pipelined execution engine (pipeline_core.v),
//   a single-port Unified Memory array (unified_mem.v), an active structural
//   contention arbiter with single-cycle bubble injection, and the 32-bit
//   Hardware Performance Telemetry Engine (phase2_telemetry.v).
//
// Structural Hazard Microarchitecture:
//   - Unlike the Harvard architecture which features physically split I & D buses,
//     the Von Neumann architecture forces Instruction Fetch (IF stage) and
//     Operand Load/Store (MEM stage) to compete for a single shared memory port.
//   - Contention Resolution Policy:
//       1. Older in-flight transaction in MEM stage (LW or SW) is given priority.
//       2. The shared memory bus multiplexer routes address, data, and byte enables
//          from the MEM stage to the unified memory array.
//       3. The Fetch stage is stalled by asserting stall_fetch = 1 (freezing PC).
//       4. A hardware pipeline bubble (NOP: addi x0, x0, 0) is inserted into
//          the IF/ID pipeline register, proving the structural hazard penalty.
//       5. On the subsequent cycle, the MEM stage transaction completes and moves
//          to WB, freeing the shared bus for the deferred instruction fetch.
//
// Telemetry Integration:
//   - Integrates phase2_telemetry.v to track total clock cycles, retired instructions,
//     injected pipeline bubbles, structural stalls, CPI, IPC, and speedup over Harvard.
//
// Standard: Verilog-2001 Synthesizable (Xilinx Artix-7 Compatible)
// =============================================================================

`timescale 1ns / 1ps

module unified_pipeline_top #(
    parameter DATA_WIDTH    = 32,
    parameter ADDR_WIDTH    = 32,
    parameter MEM_DEPTH     = 256,              // 256 words = 1024 Bytes (1 KB)
    parameter MEM_INIT_FILE = "",
    parameter RESET_PC      = 32'h0000_0000,
    parameter SYNC_READ     = 0                 // 0: Combinational read, 1: Registered BRAM read
)(
    input  wire                   clk,
    input  wire                   rst,

    // External Global Stall (e.g. multi-cycle external bus stall)
    input  wire                   ext_stall,

    // Telemetry Engine Configuration
    input  wire                   telemetry_en,
    input  wire                   telemetry_clear,

    // Diagnostic & Telemetry Status Probes
    output wire [31:0]            probe_if_pc,
    output wire [31:0]            probe_id_pc,
    output wire [31:0]            probe_ex_pc,
    output wire [31:0]            probe_mem_pc,
    output wire [31:0]            probe_wb_pc,
    output wire [31:0]            probe_wb_data,
    output wire [4:0]             probe_wb_rd,
    output wire                   probe_wb_reg_write,
    output wire                   probe_load_use_hazard,
    output wire                   probe_branch_taken,
    output wire                   probe_instr_retired,

    // Structural Hazard & Arbiter Status
    output wire                   structural_contention,
    output wire                   bubble_inserted,
    output wire                   grant_instr,
    output wire                   grant_data,

    // Memory Verification Snooping Port (Read-only for testbenches)
    input  wire [ADDR_WIDTH-1:0]  snoop_addr,
    output wire [DATA_WIDTH-1:0]  snoop_data,

    // Performance Telemetry Outputs
    output wire [31:0]            telemetry_cycle_count,
    output wire [31:0]            telemetry_retired_count,
    output wire [31:0]            telemetry_bubble_count,
    output wire [31:0]            telemetry_structural_stall_count,
    output wire [31:0]            telemetry_load_count,
    output wire [31:0]            telemetry_store_count,
    output wire [31:0]            telemetry_total_mem_ops,
    output wire [31:0]            telemetry_cpi_x1000,
    output wire [31:0]            telemetry_speedup_x1000
);

    // =========================================================================
    // 1. Pipeline Core Interconnect Signals
    // =========================================================================
    // Instruction Fetch Bus
    wire                   core_imem_read_en;
    wire [ADDR_WIDTH-1:0]  core_imem_addr;
    wire [DATA_WIDTH-1:0]  core_imem_rdata;

    // Data Memory Access Bus
    wire                   core_dmem_read_en;
    wire                   core_dmem_write_en;
    wire [3:0]             core_dmem_byte_en;
    wire [ADDR_WIDTH-1:0]  core_dmem_addr;
    wire [DATA_WIDTH-1:0]  core_dmem_wdata;
    wire [DATA_WIDTH-1:0]  core_dmem_rdata;

    // Core Hazard Feedback
    wire                   core_stall_fetch;

    // =========================================================================
    // 2. Structural Hazard Detection & Memory Bus Arbitration Logic
    // =========================================================================
    // Contention occurs when the MEM stage issues a data load (LW) or data store (SW)
    // while the IF stage is concurrently attempting to fetch an instruction.
    wire dmem_active = core_dmem_read_en | core_dmem_write_en;
    wire imem_active = core_imem_read_en;

    // Detect collision on the single physical memory port
    assign structural_contention = dmem_active & imem_active;
    assign bubble_inserted       = structural_contention;

    // In Von Neumann architecture, the data memory transaction takes absolute priority.
    // The instruction fetch is stalled and delayed by 1 cycle via stall_fetch.
    assign grant_data  = dmem_active;
    assign grant_instr = ~dmem_active;

    // Structural fetch stall signal driven into the pipeline core:
    // Holds the PC and inserts a NOP bubble into IF/ID register.
    assign core_stall_fetch = structural_contention;

    // =========================================================================
    // 3. Unified Memory Bus Multiplexer
    // =========================================================================
    reg                   mem_read_mux;
    reg                   mem_write_mux;
    reg  [3:0]            mem_byte_en_mux;
    reg  [ADDR_WIDTH-1:0] mem_addr_mux;
    reg  [DATA_WIDTH-1:0] mem_wdata_mux;
    wire [DATA_WIDTH-1:0] mem_rdata_mux;

    always @(*) begin
        if (dmem_active) begin
            // Port granted to MEM Stage (Data Load / Store)
            mem_read_mux    = core_dmem_read_en;
            mem_write_mux   = core_dmem_write_en;
            mem_byte_en_mux = core_dmem_byte_en;
            mem_addr_mux    = core_dmem_addr;
            mem_wdata_mux   = core_dmem_wdata;
        end else begin
            // Port granted to IF Stage (Instruction Fetch)
            mem_read_mux    = core_imem_read_en;
            mem_write_mux   = 1'b0;
            mem_byte_en_mux = 4'b1111;
            mem_addr_mux    = core_imem_addr;
            mem_wdata_mux   = 32'd0;
        end
    end

    // Route return data back to appropriate core stages
    // If MEM is using the bus, IF receives a NOP bubble (32'h00000013)
    assign core_imem_rdata = (dmem_active) ? 32'h00000013 : mem_rdata_mux;
    assign core_dmem_rdata = mem_rdata_mux;

    // =========================================================================
    // 4. Instantiate Pipelined RV32I Processor Core (pipeline_core.v)
    // =========================================================================
    pipeline_core #(
        .RESET_PC (RESET_PC)
    ) u_pipeline_core (
        .clk                   (clk),
        .rst                   (rst),
        .stall                 (ext_stall),
        .stall_fetch           (core_stall_fetch),
        .imem_read_en          (core_imem_read_en),
        .imem_addr             (core_imem_addr),
        .imem_rdata            (core_imem_rdata),
        .dmem_read_en          (core_dmem_read_en),
        .dmem_write_en         (core_dmem_write_en),
        .dmem_byte_enable      (core_dmem_byte_en),
        .dmem_addr             (core_dmem_addr),
        .dmem_wdata            (core_dmem_wdata),
        .dmem_rdata            (core_dmem_rdata),
        .probe_if_pc           (probe_if_pc),
        .probe_id_pc           (probe_id_pc),
        .probe_ex_pc           (probe_ex_pc),
        .probe_mem_pc          (probe_mem_pc),
        .probe_wb_pc           (probe_wb_pc),
        .probe_wb_data         (probe_wb_data),
        .probe_wb_rd           (probe_wb_rd),
        .probe_wb_reg_write    (probe_wb_reg_write),
        .probe_load_use_hazard (probe_load_use_hazard),
        .probe_branch_taken    (probe_branch_taken),
        .probe_instr_retired   (probe_instr_retired)
    );

    // =========================================================================
    // 5. Instantiate Unified Single-Port Memory Array (unified_mem.v)
    // =========================================================================
    unified_mem #(
        .DATA_WIDTH    (DATA_WIDTH),
        .ADDR_WIDTH    (ADDR_WIDTH),
        .MEM_DEPTH     (MEM_DEPTH),
        .MEM_INIT_FILE (MEM_INIT_FILE),
        .SYNC_READ     (SYNC_READ)
    ) u_unified_mem (
        .clk         (clk),
        .rst         (rst),
        .mem_read    (mem_read_mux),
        .mem_write   (mem_write_mux),
        .byte_enable (mem_byte_en_mux),
        .addr        (mem_addr_mux),
        .write_data  (mem_wdata_mux),
        .read_data   (mem_rdata_mux)
    );

    // Memory Verification Snoop Port (word-aligned combinational probe)
    wire [$clog2(MEM_DEPTH)-1:0] snoop_word_idx = snoop_addr[$clog2(MEM_DEPTH)+1:2];
    assign snoop_data = (snoop_word_idx < MEM_DEPTH) ? u_unified_mem.memory[snoop_word_idx] : 32'd0;

    // =========================================================================
    // 6. Instantiate 32-Bit Hardware Performance Telemetry Engine
    // =========================================================================
    phase2_telemetry #(
        .DATA_WIDTH (DATA_WIDTH)
    ) u_telemetry (
        .clk                    (clk),
        .rst                    (rst),
        .enable                 (telemetry_en),
        .clear                  (telemetry_clear),
        .probe_instr_retired    (probe_instr_retired),
        .probe_structural_stall (structural_contention),
        .probe_bubble_inserted  (bubble_inserted),
        .probe_load_use_hazard  (probe_load_use_hazard),
        .probe_branch_taken     (probe_branch_taken),
        .probe_mem_read         (core_dmem_read_en),
        .probe_mem_write        (core_dmem_write_en),
        .probe_icache_hit       (1'b0), // Baseline Von Neumann has no cache
        .probe_icache_miss      (1'b0),
        .probe_dcache_hit       (1'b0),
        .probe_dcache_miss      (1'b0),
        .cycle_count            (telemetry_cycle_count),
        .instr_retired_count    (telemetry_retired_count),
        .bubble_count           (telemetry_bubble_count),
        .structural_stall_count (telemetry_structural_stall_count),
        .load_use_hazard_count  (),
        .branch_flush_count     (),
        .load_count             (telemetry_load_count),
        .store_count            (telemetry_store_count),
        .total_mem_access_count (telemetry_total_mem_ops),
        .icache_hit_count       (),
        .icache_miss_count      (),
        .dcache_hit_count       (),
        .dcache_miss_count      (),
        .cpi_x1000              (telemetry_cpi_x1000),
        .ipc_x1000              (),
        .icache_hit_rate_x1000  (),
        .dcache_hit_rate_x1000  (),
        .mem_intensity_x1000    (),
        .speedup_x1000          (telemetry_speedup_x1000)
    );

endmodule
