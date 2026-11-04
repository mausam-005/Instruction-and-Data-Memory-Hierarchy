`timescale 1ns / 1ps
// =============================================================================
// Module: von_neumann_top
// Description:
//   Top-level baseline Von Neumann Memory Subsystem. Integrates a single-port
//   unified RAM (unified_mem.v) with a memory bus arbiter (mem_arbiter.v).
//
//   Structural bottleneck behavior:
//     - Simultaneous instruction fetch and data memory access cannot execute
//       concurrently due to a single shared physical memory port.
//     - The arbiter prioritizes the data path, injects a single-cycle stall
//       into the instruction/CPU pipeline, and serves the deferred instruction
//       fetch on the next clock cycle.
//     - Integrated hardware performance counters track cycles, stalls,
//       contention events, instruction fetches, and data accesses.
// =============================================================================

module von_neumann_top #(
    parameter DATA_WIDTH    = 32,
    parameter ADDR_WIDTH    = 32,
    parameter MEM_DEPTH     = 256,
    parameter MEM_INIT_FILE = ""
)(
    input  wire                  clk,
    input  wire                  rst,

    // Instruction Port (Fetch Path)
    input  wire                  instr_read_en,
    input  wire [ADDR_WIDTH-1:0] instr_addr,
    output wire [DATA_WIDTH-1:0] instr_data,

    // Data Port (Load / Store Path)
    input  wire                  data_read_en,
    input  wire                  data_write_en,
    input  wire [3:0]            data_byte_enable,
    input  wire [ADDR_WIDTH-1:0] data_addr,
    input  wire [DATA_WIDTH-1:0] data_wdata,
    output wire [DATA_WIDTH-1:0] data_rdata,

    // Control & Telemetry Status Signals
    output wire                  stall,
    output wire                  grant_instr,
    output wire                  grant_data,
    output wire [1:0]            arb_state,

    // Hardware Performance & Telemetry Counters
    output reg  [31:0]           cycle_count,
    output reg  [31:0]           stall_count,
    output reg  [31:0]           contention_count,
    output reg  [31:0]           total_fetch_count,
    output reg  [31:0]           total_data_access_count
);

    // -------------------------------------------------------------------------
    // Internal Interconnect: Arbiter to Unified Memory
    // -------------------------------------------------------------------------
    wire                  mem_read;
    wire                  mem_write;
    wire [3:0]            mem_byte_enable;
    wire [ADDR_WIDTH-1:0] mem_addr;
    wire [DATA_WIDTH-1:0] mem_wdata;
    wire [DATA_WIDTH-1:0] mem_rdata;

    // -------------------------------------------------------------------------
    // Telemetry Counter Logic
    // -------------------------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            cycle_count             <= 32'd0;
            stall_count             <= 32'd0;
            contention_count        <= 32'd0;
            total_fetch_count       <= 32'd0;
            total_data_access_count <= 32'd0;
        end else begin
            cycle_count <= cycle_count + 1'b1;

            if (stall) begin
                stall_count      <= stall_count + 1'b1;
                contention_count <= contention_count + 1'b1;
            end

            if (grant_instr && instr_read_en) begin
                total_fetch_count <= total_fetch_count + 1'b1;
            end

            if (grant_data && (data_read_en || data_write_en)) begin
                total_data_access_count <= total_data_access_count + 1'b1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Memory Bus Arbiter Instance
    // -------------------------------------------------------------------------
    mem_arbiter #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH)
    ) u_mem_arbiter (
        .clk              (clk),
        .rst              (rst),
        .instr_read_en    (instr_read_en),
        .instr_addr       (instr_addr),
        .instr_data       (instr_data),
        .data_read_en     (data_read_en),
        .data_write_en    (data_write_en),
        .data_byte_enable (data_byte_enable),
        .data_addr        (data_addr),
        .data_wdata       (data_wdata),
        .data_rdata       (data_rdata),
        .grant_instr      (grant_instr),
        .grant_data       (grant_data),
        .arb_state        (arb_state),
        .stall            (stall),
        .mem_read         (mem_read),
        .mem_write        (mem_write),
        .mem_byte_enable  (mem_byte_enable),
        .mem_addr         (mem_addr),
        .mem_wdata        (mem_wdata),
        .mem_rdata        (mem_rdata)
    );

    // -------------------------------------------------------------------------
    // Unified Shared Memory Instance (1 KB)
    // -------------------------------------------------------------------------
    unified_mem #(
        .DATA_WIDTH    (DATA_WIDTH),
        .ADDR_WIDTH    (ADDR_WIDTH),
        .MEM_DEPTH     (MEM_DEPTH),
        .MEM_INIT_FILE (MEM_INIT_FILE),
        .SYNC_READ     (0)
    ) u_unified_mem (
        .clk           (clk),
        .rst           (rst),
        .mem_read      (mem_read),
        .mem_write     (mem_write),
        .byte_enable   (mem_byte_enable),
        .addr          (mem_addr),
        .write_data    (mem_wdata),
        .read_data     (mem_rdata)
    );

endmodule

