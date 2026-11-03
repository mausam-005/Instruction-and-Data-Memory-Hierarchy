`timescale 1ns / 1ps
// =============================================================================
// Module: harvard_top
// Project: Instruction and Data Memory Hierarchy
// Description:
//   Top-level Harvard Memory Subsystem integrating independent Instruction
//   and Data Memory banks. Allows concurrent, non-blocking instruction fetch
//   and data read/write on the exact same clock edge.
//   Includes built-in hardware performance monitoring counters for:
//     - Total clock cycles
//     - Simultaneous memory accesses (Fetch + Load/Store concurrency)
//     - Total instruction fetches & total data accesses
// =============================================================================

module harvard_top #(
    parameter DATA_WIDTH        = 32,
    parameter ADDR_WIDTH        = 32,
    parameter IMEM_DEPTH        = 256,
    parameter DMEM_DEPTH        = 256,
    parameter IMEM_INIT_FILE    = "benchmarks/sample_prog.mem",
    parameter DMEM_INIT_FILE    = "",
    parameter SYNC_READ         = 0
)(
    input  wire                  clk,
    input  wire                  rst,

    // -------------------------------------------------------------------------
    // Instruction Memory Interface (Fetch Path)
    // -------------------------------------------------------------------------
    input  wire                  instr_read_en,
    input  wire [ADDR_WIDTH-1:0] instr_addr,
    output wire [DATA_WIDTH-1:0] instr_data,

    // -------------------------------------------------------------------------
    // Data Memory Interface (Load / Store Path)
    // -------------------------------------------------------------------------
    input  wire                  data_read_en,
    input  wire                  data_write_en,
    input  wire [3:0]            data_byte_enable,
    input  wire [ADDR_WIDTH-1:0] data_addr,
    input  wire [DATA_WIDTH-1:0] data_wdata,
    output wire [DATA_WIDTH-1:0] data_rdata,

    // -------------------------------------------------------------------------
    // Hardware Performance & Telemetry Counters
    // -------------------------------------------------------------------------
    output wire                  simultaneous_access,
    output reg  [31:0]           simultaneous_access_count,
    output reg  [31:0]           total_fetch_count,
    output reg  [31:0]           total_data_access_count,
    output reg  [31:0]           cycle_count
);

    // -------------------------------------------------------------------------
    // Concurrency Detection
    // -------------------------------------------------------------------------
    // High when instruction fetch and data read/write occur in the exact same cycle
    assign simultaneous_access = instr_read_en && (data_read_en || data_write_en);

    // -------------------------------------------------------------------------
    // Performance Telemetry Logic
    // -------------------------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            cycle_count               <= 32'd0;
            simultaneous_access_count <= 32'd0;
            total_fetch_count         <= 32'd0;
            total_data_access_count   <= 32'd0;
        end else begin
            cycle_count <= cycle_count + 1'b1;

            if (instr_read_en)
                total_fetch_count <= total_fetch_count + 1'b1;

            if (data_read_en || data_write_en)
                total_data_access_count <= total_data_access_count + 1'b1;

            if (simultaneous_access)
                simultaneous_access_count <= simultaneous_access_count + 1'b1;
        end
    end

    // -------------------------------------------------------------------------
    // Dedicated Instruction Memory Instance
    // -------------------------------------------------------------------------
    instruction_mem #(
        .DATA_WIDTH    (DATA_WIDTH),
        .ADDR_WIDTH    (ADDR_WIDTH),
        .MEM_DEPTH     (IMEM_DEPTH),
        .MEM_INIT_FILE (IMEM_INIT_FILE),
        .SYNC_READ     (SYNC_READ)
    ) u_instruction_mem (
        .clk           (clk),
        .rst           (rst),
        .read_en       (instr_read_en),
        .addr          (instr_addr),
        .instruction   (instr_data)
    );

    // -------------------------------------------------------------------------
    // Dedicated Data Memory Instance
    // -------------------------------------------------------------------------
    data_mem #(
        .DATA_WIDTH    (DATA_WIDTH),
        .ADDR_WIDTH    (ADDR_WIDTH),
        .MEM_DEPTH     (DMEM_DEPTH),
        .MEM_INIT_FILE (DMEM_INIT_FILE),
        .SYNC_READ     (SYNC_READ)
    ) u_data_mem (
        .clk           (clk),
        .rst           (rst),
        .mem_read      (data_read_en),
        .mem_write     (data_write_en),
        .byte_enable   (data_byte_enable),
        .addr          (data_addr),
        .write_data    (data_wdata),
        .read_data     (data_rdata)
    );

endmodule

