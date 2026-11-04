`timescale 1ns / 1ps
// =============================================================================
// Module: unified_mem
// Description:
//   Single-port shared 1 KB memory (256 words x 32 bits = 1024 Bytes) for
//   the baseline Von Neumann memory subsystem. Instructions and data share
//   the exact same physical memory array and single read/write port.
//   Supports initial memory preload via $readmemh, word-aligned addressing
//   (addr[9:2]), and byte-enable write masking.
// =============================================================================

module unified_mem #(
    parameter DATA_WIDTH    = 32,
    parameter ADDR_WIDTH    = 32,
    parameter MEM_DEPTH     = 256,               // 256 words = 1024 Bytes (1 KB)
    parameter ADDR_BITS     = $clog2(MEM_DEPTH), // 8-bit index for 256 words
    parameter MEM_INIT_FILE = "",
    parameter SYNC_READ     = 0                  // 0: Asynchronous read, 1: Synchronous read
)(
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  mem_read,
    input  wire                  mem_write,
    input  wire [3:0]            byte_enable,    // [3]=Byte3, [2]=Byte2, [1]=Byte1, [0]=Byte0
    input  wire [ADDR_WIDTH-1:0] addr,           // Byte address (word aligned: [ADDR_BITS+1:2])
    input  wire [DATA_WIDTH-1:0] write_data,
    output wire [DATA_WIDTH-1:0] read_data
);

    // Internal shared memory array (MEM_DEPTH words x DATA_WIDTH bits)
    reg [DATA_WIDTH-1:0] memory [0:MEM_DEPTH-1];

    // Word address calculation (discard lower 2 bits for 32-bit alignment)
    wire [ADDR_BITS-1:0] word_idx = addr[ADDR_BITS+1:2];

    // Memory array initialization
    integer i;
    initial begin
        for (i = 0; i < MEM_DEPTH; i = i + 1) begin
            memory[i] = 32'h00000013; // Default to RV32I NOP (addi x0, x0, 0)
        end
        if (MEM_INIT_FILE != "") begin
            $display("[unified_mem] Loading initial memory image from %s", MEM_INIT_FILE);
            $readmemh(MEM_INIT_FILE, memory);
        end
    end

    // Synchronous write logic with byte-enable masking
    always @(posedge clk) begin
        if (mem_write && (word_idx < MEM_DEPTH)) begin
            if (byte_enable[0]) memory[word_idx][7:0]   <= write_data[7:0];
            if (byte_enable[1]) memory[word_idx][15:8]  <= write_data[15:8];
            if (byte_enable[2]) memory[word_idx][23:16] <= write_data[23:16];
            if (byte_enable[3]) memory[word_idx][31:24] <= write_data[31:24];
        end
    end

    // Read logic (supports asynchronous single-cycle mode and synchronous mode)
    generate
        if (SYNC_READ == 1) begin : gen_sync_read
            reg [DATA_WIDTH-1:0] rdata_reg;
            always @(posedge clk or posedge rst) begin
                if (rst) begin
                    rdata_reg <= 32'h00000000;
                end else if (mem_read) begin
                    if (word_idx < MEM_DEPTH) begin
                        rdata_reg <= memory[word_idx];
                    end else begin
                        rdata_reg <= 32'h00000000;
                    end
                end
            end
            assign read_data = rdata_reg;
        end else begin : gen_async_read
            assign read_data = (mem_read && (word_idx < MEM_DEPTH)) ? memory[word_idx] : 32'h00000000;
        end
    endgenerate

endmodule

