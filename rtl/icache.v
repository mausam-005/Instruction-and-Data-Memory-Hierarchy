// =============================================================================
// Project: Instruction and Data Memory Hierarchy (Phase II)
// Module : icache.v
// Author : Mausam Kumar Dwivedi (Role 1: Lead Architect)
// Description: L1 Direct-Mapped Instruction Cache with 16-byte (4-word) cache lines,
//              tag comparison, single-cycle hit path, burst refill FSM, and
//              hardware hit/miss telemetry counters.
// Standard   : Verilog-2001 Synthesizable
// =============================================================================

`timescale 1ns / 1ps

module icache #(
    parameter NUM_LINES   = 8,   // 8 cache lines (3 index bits)
    parameter WORDS_PER_LINE = 4, // 4 words = 16 bytes per line (2 word offset bits)
    parameter DATA_WIDTH  = 32,  // 32-bit instruction word
    parameter ADDR_WIDTH  = 32   // 32-bit byte address
)(
    input  wire                   clk,
    input  wire                   rst_n,

    // -------------------------------------------------------------------------
    // CPU Core Interface (Fetch Stage / IF)
    // -------------------------------------------------------------------------
    input  wire [ADDR_WIDTH-1:0]  cpu_addr,       // Byte address from PC
    input  wire                   cpu_req,        // Active high instruction fetch request
    output reg  [DATA_WIDTH-1:0]  cpu_rdata,      // 32-bit instruction to IF/ID register
    output reg                    cpu_hit,        // Cache hit status (high when hit)
    output wire                   cpu_stall,      // Pipeline stall (freezes PC/pipeline on miss)

    // -------------------------------------------------------------------------
    // Lower Memory / Cache Refill Arbiter Interface
    // -------------------------------------------------------------------------
    output reg  [ADDR_WIDTH-1:0]  mem_addr,       // 16-byte aligned base address for refill
    output reg                    mem_req,        // Refill burst request asserted on miss
    input  wire [127:0]           mem_line_data,  // 128-bit cache line (4 x 32-bit words)
    input  wire                   mem_ready,      // Memory ready / transfer acknowledge

    // -------------------------------------------------------------------------
    // Hardware Telemetry & Performance Counters
    // -------------------------------------------------------------------------
    output reg  [31:0]            icache_hits,
    output reg  [31:0]            icache_misses,
    output reg  [31:0]            icache_accesses
);

    // -------------------------------------------------------------------------
    // Address Field Decomposition
    // -------------------------------------------------------------------------
    // Byte offset : addr[1:0]  (2 bits, word-aligned)
    // Word offset : addr[3:2]  (2 bits, selects word 0, 1, 2, or 3)
    // Line index  : addr[6:4]  (3 bits, selects 1 of 8 lines)
    // Tag         : addr[31:7] (25 bits tag)
    // -------------------------------------------------------------------------
    localparam BYTE_OFFSET_BITS = 2;
    localparam WORD_OFFSET_BITS = 2;
    localparam INDEX_BITS       = 3;
    localparam TAG_BITS         = ADDR_WIDTH - INDEX_BITS - WORD_OFFSET_BITS - BYTE_OFFSET_BITS; // 25 bits

    wire [WORD_OFFSET_BITS-1:0] word_offset = cpu_addr[3:2];
    wire [INDEX_BITS-1:0]       line_index  = cpu_addr[6:4];
    wire [TAG_BITS-1:0]         addr_tag    = cpu_addr[31:7];

    // -------------------------------------------------------------------------
    // Cache Storage Arrays
    // -------------------------------------------------------------------------
    reg                 valid_array [0:NUM_LINES-1];
    reg [TAG_BITS-1:0]  tag_array   [0:NUM_LINES-1];
    reg [DATA_WIDTH-1:0] data_array  [0:NUM_LINES-1][0:WORDS_PER_LINE-1];

    // -------------------------------------------------------------------------
    // FSM States for Cache Line Allocation
    // -------------------------------------------------------------------------
    localparam STATE_IDLE        = 2'b00;
    localparam STATE_ALLOCATE    = 2'b01;
    localparam STATE_SERVE_MISS  = 2'b10;

    reg [1:0] state, next_state;

    // Line hit detection logic
    wire is_valid = valid_array[line_index];
    wire is_match = (tag_array[line_index] == addr_tag);
    wire line_hit = cpu_req && is_valid && is_match;

    // Stall CPU whenever a fetch request is pending and we don't have a hit in IDLE
    assign cpu_stall = cpu_req && (!line_hit || (state != STATE_IDLE));

    // -------------------------------------------------------------------------
    // Combinational Read Path (Zero extra cycles on cache hit)
    // -------------------------------------------------------------------------
    always @(*) begin
        if (state == STATE_IDLE && line_hit) begin
            cpu_rdata = data_array[line_index][word_offset];
            cpu_hit   = 1'b1;
        end else if (state == STATE_SERVE_MISS) begin
            // Serve newly refilled word immediately
            case (word_offset)
                2'b00: cpu_rdata = mem_line_data[31:0];
                2'b01: cpu_rdata = mem_line_data[63:32];
                2'b10: cpu_rdata = mem_line_data[95:64];
                2'b11: cpu_rdata = mem_line_data[127:96];
            endcase
            cpu_hit   = 1'b0; // Was originally a miss
        end else begin
            cpu_rdata = 32'h00000013; // Default NOP
            cpu_hit   = 1'b0;
        end
    end

    // -------------------------------------------------------------------------
    // Cache Controller State Machine
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
        end else begin
            state <= next_state;
        end
    end

    always @(*) begin
        next_state = state;
        mem_req    = 1'b0;
        mem_addr   = {cpu_addr[31:4], 4'b0000}; // 16-byte aligned line base

        case (state)
            STATE_IDLE: begin
                if (cpu_req && !line_hit) begin
                    // Cache Miss: initiate burst refill from memory
                    mem_req    = 1'b1;
                    next_state = STATE_ALLOCATE;
                end
            end

            STATE_ALLOCATE: begin
                mem_req = 1'b1;
                if (mem_ready) begin
                    next_state = STATE_SERVE_MISS;
                end
            end

            STATE_SERVE_MISS: begin
                // One cycle to present newly loaded word to CPU, then return to IDLE
                next_state = STATE_IDLE;
            end

            default: next_state = STATE_IDLE;
        endcase
    end

    // -------------------------------------------------------------------------
    // Cache Refill & Update Logic
    // -------------------------------------------------------------------------
    integer i, w;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < NUM_LINES; i = i + 1) begin
                valid_array[i] <= 1'b0;
                tag_array[i]   <= {TAG_BITS{1'b0}};
                for (w = 0; w < WORDS_PER_LINE; w = w + 1) begin
                    data_array[i][w] <= 32'h0;
                end
            end
        end else begin
            if (state == STATE_ALLOCATE && mem_ready) begin
                // Update line data array from 128-bit memory bus
                data_array[line_index][0] <= mem_line_data[31:0];
                data_array[line_index][1] <= mem_line_data[63:32];
                data_array[line_index][2] <= mem_line_data[95:64];
                data_array[line_index][3] <= mem_line_data[127:96];

                // Update Tag and set Valid bit
                tag_array[line_index]   <= addr_tag;
                valid_array[line_index] <= 1'b1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Hardware Telemetry Counters
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            icache_hits     <= 32'd0;
            icache_misses   <= 32'd0;
            icache_accesses <= 32'd0;
        end else begin
            if (state == STATE_IDLE && cpu_req) begin
                icache_accesses <= icache_accesses + 1'b1;
                if (line_hit) begin
                    icache_hits <= icache_hits + 1'b1;
                end else begin
                    icache_misses <= icache_misses + 1'b1;
                end
            end
        end
    end

endmodule
