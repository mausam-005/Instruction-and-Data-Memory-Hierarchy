// =============================================================================
// Project: Instruction and Data Memory Hierarchy (Phase II)
// Module : phase2_telemetry.v
// Author : Daniel Tayal (2401010140)
// Description:
//   32-bit Hardware Performance Telemetry Engine for 5-Stage RV32I Processors.
//   Monitors microarchitectural event streams in real time without injecting
//   intrusive instrumentation overhead into the execution pipeline.
//
// Tracked Architectural Metrics:
//   1. Throughput & Execution Cycles:
//      - cycle_count           : Total elapsed clock cycles
//      - instr_retired_count   : Total valid instructions retired at WB stage
//      - cpi_x1000             : Scaled Cycles Per Instruction (CPI * 1000)
//      - ipc_x1000             : Scaled Instructions Per Cycle (IPC * 1000)
//
//   2. Structural Hazards & Pipeline Bubbles:
//      - bubble_count          : Total pipeline bubbles inserted due to structural stalls
//      - structural_stall_count: Total memory port contention collision events
//      - load_use_hazard_count : Total RAW load-use data hazard stall cycles
//      - branch_flush_count    : Total control hazard speculative squash cycles
//
//   3. Memory Bus Transactions:
//      - load_count            : Total data load (LW) transactions
//      - store_count           : Total data store (SW) transactions
//      - total_mem_access_count: Aggregate data memory operations (LW + SW)
//      - mem_intensity_x1000   : Memory instruction density (Mem_Ops / Total_Instr * 1000)
//
//   4. Cache Hierarchy Statistics:
//      - icache_hit_count      : L1 Instruction Cache hits
//      - icache_miss_count     : L1 Instruction Cache misses
//      - icache_hit_rate_x1000 : Scaled I-Cache hit rate (Hits / Accesses * 1000)
//      - dcache_hit_count      : L1 Data Cache hits
//      - dcache_miss_count     : L1 Data Cache misses
//      - dcache_hit_rate_x1000 : Scaled D-Cache hit rate (Hits / Accesses * 1000)
//
//   5. Comparative Architectural Speedup:
//      - harvard_equiv_cycles  : Analytical cycles required on dual-bus Harvard hierarchy
//      - speedup_x1000         : Measured speedup factor (Cycles_VN / Cycles_Harvard * 1000)
//
// Standard: Verilog-2001 Synthesizable (Xilinx Artix-7 Compatible)
// =============================================================================

`timescale 1ns / 1ps

module phase2_telemetry #(
    parameter DATA_WIDTH = 32
)(
    input  wire                   clk,
    input  wire                   rst,
    input  wire                   enable,               // Master measurement enable gate
    input  wire                   clear,                // Synchronous counter clear

    // -------------------------------------------------------------------------
    // Core Pipeline Execution Probes
    // -------------------------------------------------------------------------
    input  wire                   probe_instr_retired,  // 1 when valid instruction commits in WB
    input  wire                   probe_structural_stall,// 1 when IF/MEM memory port contention occurs
    input  wire                   probe_bubble_inserted,// 1 when a bubble (NOP) is injected into pipeline
    input  wire                   probe_load_use_hazard,// 1 when EX stage detects RAW load-use hazard
    input  wire                   probe_branch_taken,   // 1 when branch/jump redirects PC (flush IF/ID)
    input  wire                   probe_mem_read,       // 1 when MEM stage issues LW
    input  wire                   probe_mem_write,      // 1 when MEM stage issues SW

    // -------------------------------------------------------------------------
    // Cache Hierarchy Event Probes
    // -------------------------------------------------------------------------
    input  wire                   probe_icache_hit,     // 1 on I-Cache hit
    input  wire                   probe_icache_miss,    // 1 on I-Cache miss
    input  wire                   probe_dcache_hit,     // 1 on D-Cache hit
    input  wire                   probe_dcache_miss,    // 1 on D-Cache miss

    // -------------------------------------------------------------------------
    // 32-Bit Telemetry Counter Outputs
    // -------------------------------------------------------------------------
    output reg  [31:0]            cycle_count,
    output reg  [31:0]            instr_retired_count,
    output reg  [31:0]            bubble_count,
    output reg  [31:0]            structural_stall_count,
    output reg  [31:0]            load_use_hazard_count,
    output reg  [31:0]            branch_flush_count,
    output reg  [31:0]            load_count,
    output reg  [31:0]            store_count,
    output reg  [31:0]            total_mem_access_count,

    output reg  [31:0]            icache_hit_count,
    output reg  [31:0]            icache_miss_count,
    output reg  [31:0]            dcache_hit_count,
    output reg  [31:0]            dcache_miss_count,

    // -------------------------------------------------------------------------
    // Real-Time Derived Metric Outputs (Scaled Integer Format)
    // -------------------------------------------------------------------------
    output reg  [31:0]            cpi_x1000,            // CPI * 1000 (e.g. 1250 = 1.250 CPI)
    output reg  [31:0]            ipc_x1000,            // IPC * 1000 (e.g. 800 = 0.800 IPC)
    output reg  [31:0]            icache_hit_rate_x1000,// Hit rate (0 to 1000)
    output reg  [31:0]            dcache_hit_rate_x1000,// Hit rate (0 to 1000)
    output reg  [31:0]            mem_intensity_x1000,  // (Mem_Ops / Instructions) * 1000
    output reg  [31:0]            speedup_x1000         // Speedup vs Harvard (e.g. 1210 = 1.21x)
);

    // =========================================================================
    // 1. Primary Event Accumulators
    // =========================================================================
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            cycle_count            <= 32'd0;
            instr_retired_count    <= 32'd0;
            bubble_count           <= 32'd0;
            structural_stall_count <= 32'd0;
            load_use_hazard_count  <= 32'd0;
            branch_flush_count     <= 32'd0;
            load_count             <= 32'd0;
            store_count            <= 32'd0;
            total_mem_access_count <= 32'd0;
            icache_hit_count       <= 32'd0;
            icache_miss_count      <= 32'd0;
            dcache_hit_count       <= 32'd0;
            dcache_miss_count      <= 32'd0;
        end else if (clear) begin
            cycle_count            <= 32'd0;
            instr_retired_count    <= 32'd0;
            bubble_count           <= 32'd0;
            structural_stall_count <= 32'd0;
            load_use_hazard_count  <= 32'd0;
            branch_flush_count     <= 32'd0;
            load_count             <= 32'd0;
            store_count            <= 32'd0;
            total_mem_access_count <= 32'd0;
            icache_hit_count       <= 32'd0;
            icache_miss_count      <= 32'd0;
            dcache_hit_count       <= 32'd0;
            dcache_miss_count      <= 32'd0;
        end else if (enable) begin
            cycle_count <= cycle_count + 1'b1;

            if (probe_instr_retired)
                instr_retired_count <= instr_retired_count + 1'b1;

            if (probe_bubble_inserted)
                bubble_count <= bubble_count + 1'b1;

            if (probe_structural_stall)
                structural_stall_count <= structural_stall_count + 1'b1;

            if (probe_load_use_hazard)
                load_use_hazard_count <= load_use_hazard_count + 1'b1;

            if (probe_branch_taken)
                branch_flush_count <= branch_flush_count + 1'b1;

            if (probe_mem_read) begin
                load_count             <= load_count + 1'b1;
                total_mem_access_count <= total_mem_access_count + 1'b1;
            end else if (probe_mem_write) begin
                store_count            <= store_count + 1'b1;
                total_mem_access_count <= total_mem_access_count + 1'b1;
            end

            if (probe_icache_hit)
                icache_hit_count <= icache_hit_count + 1'b1;
            if (probe_icache_miss)
                icache_miss_count <= icache_miss_count + 1'b1;

            if (probe_dcache_hit)
                dcache_hit_count <= dcache_hit_count + 1'b1;
            if (probe_dcache_miss)
                dcache_miss_count <= dcache_miss_count + 1'b1;
        end
    end

    // =========================================================================
    // 2. Analytical Metric Derivations
    // =========================================================================
    // Harvard equivalent cycle count:
    // In Harvard dual-bus architecture, structural memory stalls are 0.
    // Therefore, Harvard cycles = Total Von Neumann cycles - Structural bubbles.
    wire [31:0] harvard_equiv_cycles = (cycle_count > bubble_count) ?
                                       (cycle_count - bubble_count) : 32'd1;

    wire [31:0] total_icache_acc = icache_hit_count + icache_miss_count;
    wire [31:0] total_dcache_acc = dcache_hit_count + dcache_miss_count;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            cpi_x1000             <= 32'd1000; // Base ideal CPI = 1.000
            ipc_x1000             <= 32'd1000;
            icache_hit_rate_x1000 <= 32'd1000;
            dcache_hit_rate_x1000 <= 32'd1000;
            mem_intensity_x1000   <= 32'd0;
            speedup_x1000         <= 32'd1000;
        end else if (enable) begin
            // Cycles Per Instruction (CPI * 1000)
            if (instr_retired_count > 0) begin
                cpi_x1000 <= (cycle_count * 32'd1000) / instr_retired_count;
                ipc_x1000 <= (instr_retired_count * 32'd1000) / (cycle_count > 0 ? cycle_count : 32'd1);
                mem_intensity_x1000 <= (total_mem_access_count * 32'd1000) / instr_retired_count;
            end

            // I-Cache Hit Rate (0 to 1000)
            if (total_icache_acc > 0) begin
                icache_hit_rate_x1000 <= (icache_hit_count * 32'd1000) / total_icache_acc;
            end

            // D-Cache Hit Rate (0 to 1000)
            if (total_dcache_acc > 0) begin
                dcache_hit_rate_x1000 <= (dcache_hit_count * 32'd1000) / total_dcache_acc;
            end

            // Architectural Speedup of Harvard over Von Neumann:
            // S = Cycles_VN / Cycles_Harvard = cycle_count / (cycle_count - bubble_count)
            if (harvard_equiv_cycles > 0) begin
                speedup_x1000 <= (cycle_count * 32'd1000) / harvard_equiv_cycles;
            end
        end
    end

    // =========================================================================
    // 3. Formatted Architectural Telemetry Display Task (Simulation Diagnostic)
    // =========================================================================
    // synthesis translate_off
    task print_telemetry_report;
        input [8*64-1:0] benchmark_label;
        begin
            $display("==================================================================================");
            $display("           HARDWARE PERFORMANCE TELEMETRY ENGINE REPORT                           ");
            $display("           Workload: %0s", benchmark_label);
            $display("==================================================================================");
            $display("  [EXECUTION THROUGHPUT]");
            $display("    Total Clock Cycles Elapsed      : %0d", cycle_count);
            $display("    Total Instructions Retired      : %0d", instr_retired_count);
            $display("    Measured Cycles Per Instr (CPI) : %0d.%03d", cpi_x1000 / 1000, cpi_x1000 % 1000);
            $display("    Measured Instructions/Cycle(IPC): %0d.%03d", ipc_x1000 / 1000, ipc_x1000 % 1000);
            $display("----------------------------------------------------------------------------------");
            $display("  [STRUCTURAL HAZARD & PIPELINE BUBBLES]");
            $display("    Von Neumann Structural Stalls   : %0d", structural_stall_count);
            $display("    Injected Pipeline Bubbles       : %0d", bubble_count);
            $display("    RAW Load-Use Data Hazard Stalls : %0d", load_use_hazard_count);
            $display("    Branch/Jump Control Flushes     : %0d", branch_flush_count);
            $display("----------------------------------------------------------------------------------");
            $display("  [MEMORY HIERARCHY ACCESS PATTERN]");
            $display("    Data Load Transactions  (LW)    : %0d", load_count);
            $display("    Data Store Transactions (SW)    : %0d", store_count);
            $display("    Total Memory Operations (LW+SW) : %0d", total_mem_access_count);
            $display("    Memory Instruction Density      : %0d.%01d %%", mem_intensity_x1000 / 10, mem_intensity_x1000 % 10);
            $display("----------------------------------------------------------------------------------");
            $display("  [CACHE HIERARCHY TELEMETRY]");
            $display("    L1 I-Cache Hits / Misses        : %0d / %0d (Hit Rate: %0d.%01d%%)", 
                     icache_hit_count, icache_miss_count, icache_hit_rate_x1000 / 10, icache_hit_rate_x1000 % 10);
            $display("    L1 D-Cache Hits / Misses        : %0d / %0d (Hit Rate: %0d.%01d%%)", 
                     dcache_hit_count, dcache_miss_count, dcache_hit_rate_x1000 / 10, dcache_hit_rate_x1000 % 10);
            $display("----------------------------------------------------------------------------------");
            $display("  [ARCHITECTURAL COMPARISON & SPEEDUP]");
            $display("    Von Neumann Baseline Cycles     : %0d", cycle_count);
            $display("    Harvard Dual-Bus Equiv. Cycles  : %0d", harvard_equiv_cycles);
            $display("    Eliminated Structural Stalls    : %0d", bubble_count);
            $display("    Realized Harvard Speedup Factor : %0d.%03dx (%0d.%02d%% faster)",
                     speedup_x1000 / 1000, speedup_x1000 % 1000,
                     ((cycle_count - harvard_equiv_cycles) * 10000) / (cycle_count > 0 ? cycle_count : 1) / 100,
                     (((cycle_count - harvard_equiv_cycles) * 10000) / (cycle_count > 0 ? cycle_count : 1)) % 100);
            $display("==================================================================================");
        end
    endtask
    // synthesis translate_on

endmodule
