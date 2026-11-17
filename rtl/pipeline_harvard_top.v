// =============================================================================
// Project: Instruction and Data Memory Hierarchy (Phase II)
// Module : pipeline_harvard_top.v
// Author : Mausam Kumar Dwivedi (Role 1: Lead Architect)
// Description: Top-level Pipelined Harvard Memory Subsystem with L1 I-Cache,
//              decoupled L1 D-Cache interface, simultaneous access telemetry,
//              and lower-level memory refill buses.
// Standard   : Verilog-2001 Synthesizable
// =============================================================================

`timescale 1ns / 1ps

module pipeline_harvard_top #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input  wire                   clk,
    input  wire                   rst_n,

    // -------------------------------------------------------------------------
    // CPU Fetch Stage Interface (IF Stage)
    // -------------------------------------------------------------------------
    input  wire [ADDR_WIDTH-1:0]  if_pc_addr,       // Program Counter address
    input  wire                   if_req,           // Instruction fetch request
    output wire [DATA_WIDTH-1:0]  if_instr_data,    // Instruction word to IF/ID
    output wire                   if_cache_hit,     // I-Cache hit status
    output wire                   if_stall,         // Freeze pipeline on I-Cache miss

    // -------------------------------------------------------------------------
    // CPU Memory Stage Interface (MEM Stage)
    // -------------------------------------------------------------------------
    input  wire [ADDR_WIDTH-1:0]  mem_addr,         // Data address from EX/MEM
    input  wire [DATA_WIDTH-1:0]  mem_wdata,        // Data to write (store)
    input  wire [3:0]             mem_byte_en,      // 4-bit byte enables
    input  wire                   mem_read_en,      // Data read enable (LW)
    input  wire                   mem_write_en,     // Data write enable (SW)
    output wire [DATA_WIDTH-1:0]  mem_rdata,        // Data read from D-Cache
    output wire                   mem_cache_hit,    // D-Cache hit status
    output wire                   mem_stall,        // Freeze pipeline on D-Cache miss

    // -------------------------------------------------------------------------
    // Lower Memory / Backing Bus Interfaces (To Refill Arbiter / BRAM)
    // -------------------------------------------------------------------------
    // I-Cache Refill Port
    output wire [ADDR_WIDTH-1:0]  icache_mem_addr,
    output wire                   icache_mem_req,
    input  wire [127:0]           icache_mem_line,
    input  wire                   icache_mem_ready,

    // D-Cache Refill / Write-Through Port
    output wire [ADDR_WIDTH-1:0]  dcache_mem_addr,
    output wire [DATA_WIDTH-1:0]  dcache_mem_wdata,
    output wire [3:0]             dcache_mem_byte_en,
    output wire                   dcache_mem_req,
    output wire                   dcache_mem_we,
    input  wire [127:0]           dcache_mem_line,
    input  wire                   dcache_mem_ready,

    // -------------------------------------------------------------------------
    // Global Hardware Telemetry & Concurrency Monitoring
    // -------------------------------------------------------------------------
    output wire                   simultaneous_access,
    output reg  [31:0]            simultaneous_access_count,
    output reg  [31:0]            total_fetch_count,
    output reg  [31:0]            total_data_access_count,
    output wire [31:0]            icache_hit_count,
    output wire [31:0]            icache_miss_count
);

    // -------------------------------------------------------------------------
    // 1. Instantiate L1 Instruction Cache (Authored by Mausam)
    // -------------------------------------------------------------------------
    icache #(
        .NUM_LINES(8),
        .WORDS_PER_LINE(4),
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_icache (
        .clk(clk),
        .rst_n(rst_n),
        // CPU Port
        .cpu_addr(if_pc_addr),
        .cpu_req(if_req),
        .cpu_rdata(if_instr_data),
        .cpu_hit(if_cache_hit),
        .cpu_stall(if_stall),
        // Backing Memory Refill Port
        .mem_addr(icache_mem_addr),
        .mem_req(icache_mem_req),
        .mem_line_data(icache_mem_line),
        .mem_ready(icache_mem_ready),
        // Telemetry
        .icache_hits(icache_hit_count),
        .icache_misses(icache_miss_count),
        .icache_accesses()
    );

    // -------------------------------------------------------------------------
    // 2. Concurrency Detection Logic (Harvard Principle)
    // -------------------------------------------------------------------------
    // True Harvard Concurrency: Instruction fetch in IF and Data read/write in MEM
    // occur in the exact same cycle on physically independent caches without collision.
    assign simultaneous_access = if_req && (mem_read_en || mem_write_en);

    // -------------------------------------------------------------------------
    // 3. Hardware Concurrency & Access Telemetry Accumulators
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            simultaneous_access_count <= 32'd0;
            total_fetch_count         <= 32'd0;
            total_data_access_count   <= 32'd0;
        end else begin
            if (if_req) begin
                total_fetch_count <= total_fetch_count + 1'b1;
            end
            if (mem_read_en || mem_write_en) begin
                total_data_access_count <= total_data_access_count + 1'b1;
            end
            if (simultaneous_access) begin
                simultaneous_access_count <= simultaneous_access_count + 1'b1;
            end
        end
    end

endmodule
