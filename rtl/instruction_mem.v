`timescale 1ns / 1ps
// =============================================================================
// Module: instruction_mem
// Project: Instruction and Data Memory Hierarchy
// Description:
//   Dedicated Instruction Memory (ROM / Read-Only Memory) for the Harvard
//   memory architecture. Supports configurable depth, optional initial memory
//   preload via $readmemh, and word-aligned addressing (addr[ADDR_BITS+1:2]).
//   Configurable for both combinational (asynchronous) read and clocked
//   (synchronous) read to support both single-cycle and pipelined cores.
// =============================================================================

module instruction_mem #(
    parameter DATA_WIDTH    = 32,
    parameter ADDR_WIDTH    = 32,
    parameter MEM_DEPTH     = 256,              // 256 words = 1024 Bytes (1 KB)
    parameter ADDR_BITS     = $clog2(MEM_DEPTH),// 8 bits index for 256 words
    parameter MEM_INIT_FILE = "benchmarks/sample_prog.mem",
    parameter SYNC_READ     = 0                 // 0: Asynchronous read, 1: Synchronous read
)(
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  read_en,
    input  wire [ADDR_WIDTH-1:0] addr,           // Byte address (word aligned: [ADDR_BITS+1:2])
    output wire [DATA_WIDTH-1:0] instruction
);

    // Internal memory array (MEM_DEPTH words of DATA_WIDTH bits)
    reg [DATA_WIDTH-1:0] memory [0:MEM_DEPTH-1];

    // Word address calculation (discard lower 2 bits for 32-bit alignment)
    wire [ADDR_BITS-1:0] word_idx = addr[ADDR_BITS+1:2];

    // Initialize memory array
    integer i;
    initial begin
        // Clear all entries to NOP (0x00000013 in RV32I)
        for (i = 0; i < MEM_DEPTH; i = i + 1) begin
            memory[i] = 32'h00000013;
        end
        // Load initial program file if specified
        if (MEM_INIT_FILE != "") begin
            $display("[instruction_mem] Loading instruction hex from %s", MEM_INIT_FILE);
            $readmemh(MEM_INIT_FILE, memory);
        end
    end

    // Read logic
    generate
        if (SYNC_READ == 1) begin : gen_sync_read
            // Synchronous (clocked) read - standard BRAM behavior
            reg [DATA_WIDTH-1:0] rdata_reg;
            always @(posedge clk or posedge rst) begin
                if (rst) begin
                    rdata_reg <= 32'h00000013; // Reset to NOP
                end else if (read_en) begin
                    if (word_idx < MEM_DEPTH) begin
                        rdata_reg <= memory[word_idx];
                    end else begin
                        rdata_reg <= 32'h00000000;
                    end
                end
            end
            assign instruction = rdata_reg;
        end else begin : gen_async_read
            // Asynchronous (combinational) read - zero-latency single-cycle core mode
            assign instruction = (read_en && (word_idx < MEM_DEPTH)) ? memory[word_idx] : 32'h00000000;
        end
    endgenerate

endmodule

