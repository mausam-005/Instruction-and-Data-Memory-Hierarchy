`timescale 1ns / 1ps
// =============================================================================
// Module: dcache
// Description:
//   Synthesizable direct-mapped L1 Data Cache for the RV32I memory hierarchy.
//
//   Cache Organization:
//     - Cache Size   : 256 Bytes  (16 sets x 1 way x 16-byte lines)
//     - Line Size    : 16 Bytes   (4 words x 32 bits per line)
//     - Associativity: Direct-mapped (1-way)
//     - Replacement  : N/A — direct-mapped has no replacement choice
//
//   Address Decomposition (32-bit byte address):
//     [31:8] Tag    (24 bits) — identifies which memory block
//     [7:4]  Index  ( 4 bits) — selects one of 16 cache sets
//     [3:2]  Offset ( 2 bits) — selects one of 4 words within a line
//     [1:0]  Byte   ( 2 bits) — byte offset within word (used by CPU, not cache)
//
//   Write Policy: Write-Through with write-allocate-on-miss.
//     - On a write HIT:  Write to cache data array immediately (byte-masked)
//                        AND issue write-through to backing unified memory.
//     - On a write MISS: Trigger a line refill from unified memory (REFILL state),
//                        then write the word into the freshly loaded line
//                        AND write-through to unified memory.
//
//   Dirty/Valid Tracking:
//     - valid[set] : set when line is loaded from memory.
//     - dirty[set] : set when any byte of the line has been written.
//       Write-through ensures memory always has the latest data, so dirty
//       is maintained for telemetry and future write-back extension readiness.
//
//   Byte-Enable Write Masking:
//     - Supports RV32I SB (4'b0001/0010/0100/1000),
//                    SH (4'b0011 / 4'b1100),
//                    SW (4'b1111) with the standard byte_enable[3:0] interface.
//
//   Cache FSM States:
//     IDLE    (2'b00) : Ready to accept CPU requests.
//     REFILL  (2'b01) : Burst-fetching one full cache line from memory
//                       (4 consecutive word reads, one per cycle).
//     WTHROUGH(2'b10) : Issuing a write-through word to unified memory
//                       and waiting for acknowledgment.
//
//   Performance Counters:
//     - hit_count, miss_count, write_hit_count, write_miss_count — telemetry.
// =============================================================================

module dcache #(
    parameter DATA_WIDTH     = 32,
    parameter ADDR_WIDTH     = 32,
    parameter NUM_SETS       = 16,          // 16 direct-mapped sets
    parameter WORDS_PER_LINE = 4,           // 4 words (16 bytes) per cache line
    parameter TAG_WIDTH      = 24,          // addr[31:8]
    parameter INDEX_WIDTH    = 4,           // addr[7:4]  — log2(NUM_SETS)
    parameter OFFSET_WIDTH   = 2            // addr[3:2]  — log2(WORDS_PER_LINE)
)(
    input  wire                  clk,
    input  wire                  rst,

    // -------------------------------------------------------------------------
    // CPU-Side Interface
    // -------------------------------------------------------------------------
    input  wire                  cpu_read_en,       // CPU requests a load
    input  wire                  cpu_write_en,      // CPU requests a store
    input  wire [3:0]            cpu_byte_enable,   // SB=0001/0010/0100/1000, SH=0011/1100, SW=1111
    input  wire [ADDR_WIDTH-1:0] cpu_addr,          // Byte address from CPU
    input  wire [DATA_WIDTH-1:0] cpu_wdata,         // Store data from CPU
    output reg  [DATA_WIDTH-1:0] cpu_rdata,         // Load data returned to CPU
    output wire                  cpu_stall,         // Stall CPU while servicing miss or write-through

    // -------------------------------------------------------------------------
    // Memory-Side Interface (connects to cache_arbiter / unified_mem)
    // -------------------------------------------------------------------------
    output reg                   mem_read_en,       // Request a word read from memory
    output reg                   mem_write_en,      // Request a word write (write-through)
    output reg  [3:0]            mem_byte_enable,   // Byte enables forwarded to memory
    output reg  [ADDR_WIDTH-1:0] mem_addr,          // Word-aligned address to memory
    output reg  [DATA_WIDTH-1:0] mem_wdata,         // Write data forwarded to memory
    input  wire [DATA_WIDTH-1:0] mem_rdata,         // Data returned from memory
    input  wire                  mem_ready,         // Memory signals data is valid / write accepted

    // -------------------------------------------------------------------------
    // Cache Status & Telemetry
    // -------------------------------------------------------------------------
    output wire                  cache_hit,
    output wire                  cache_miss,
    output reg  [31:0]           hit_count,
    output reg  [31:0]           miss_count,
    output reg  [31:0]           write_hit_count,
    output reg  [31:0]           write_miss_count
);

    // =========================================================================
    // Cache Storage Arrays
    // =========================================================================
    reg [TAG_WIDTH-1:0]                      tag_array   [0:NUM_SETS-1];
    reg [DATA_WIDTH-1:0]                     data_array  [0:NUM_SETS-1][0:WORDS_PER_LINE-1];
    reg                                      valid_array [0:NUM_SETS-1];
    reg                                      dirty_array [0:NUM_SETS-1];

    // =========================================================================
    // Address Decomposition
    // =========================================================================
    wire [TAG_WIDTH-1:0]    req_tag    = cpu_addr[ADDR_WIDTH-1 : ADDR_WIDTH-TAG_WIDTH]; // [31:8]
    wire [INDEX_WIDTH-1:0]  req_index  = cpu_addr[INDEX_WIDTH+OFFSET_WIDTH+1 : OFFSET_WIDTH+2]; // [7:4]
    wire [OFFSET_WIDTH-1:0] req_offset = cpu_addr[OFFSET_WIDTH+1 : 2]; // [3:2]

    // =========================================================================
    // Hit / Miss Detection (purely combinational)
    // =========================================================================
    wire tag_match   = (tag_array[req_index] == req_tag);
    wire line_valid  = valid_array[req_index];
    wire hit_detect  = line_valid & tag_match & (cpu_read_en | cpu_write_en);
    wire miss_detect = (cpu_read_en | cpu_write_en) & ~hit_detect;

    assign cache_hit  = hit_detect;
    assign cache_miss = miss_detect;

    // =========================================================================
    // FSM State Encoding
    // =========================================================================
    localparam [1:0] IDLE     = 2'b00;
    localparam [1:0] REFILL   = 2'b01;
    localparam [1:0] WTHROUGH = 2'b10;

    reg [1:0] state_reg, next_state;
    reg [OFFSET_WIDTH-1:0] refill_word;     // Which word in the refill burst we're on
    reg pending_write;                       // Write was waiting for refill to complete
    reg [3:0]  pending_be;
    reg [DATA_WIDTH-1:0] pending_wdata;
    reg [ADDR_WIDTH-1:0] pending_addr;

    // =========================================================================
    // CPU Stall
    // =========================================================================
    // CPU is stalled whenever the cache is not in IDLE with a hit.
    assign cpu_stall = (state_reg != IDLE) | miss_detect;

    // =========================================================================
    // Synchronous FSM State Register
    // =========================================================================
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state_reg <= IDLE;
        end else begin
            state_reg <= next_state;
        end
    end

    // =========================================================================
    // Next-State Logic
    // =========================================================================
    always @(*) begin
        next_state = state_reg;
        case (state_reg)
            IDLE: begin
                if (miss_detect) begin
                    // Any miss (read or write) triggers a line refill first
                    next_state = REFILL;
                end else if (hit_detect && cpu_write_en) begin
                    // Write hit: update cache, then issue write-through
                    next_state = WTHROUGH;
                end else begin
                    next_state = IDLE;
                end
            end

            REFILL: begin
                // Stay in REFILL until all 4 words have been fetched
                if (mem_ready && (refill_word == WORDS_PER_LINE - 1)) begin
                    // If original request was a write, need WTHROUGH next
                    if (pending_write) begin
                        next_state = WTHROUGH;
                    end else begin
                        next_state = IDLE;
                    end
                end else begin
                    next_state = REFILL;
                end
            end

            WTHROUGH: begin
                if (mem_ready) begin
                    next_state = IDLE;
                end else begin
                    next_state = WTHROUGH;
                end
            end

            default: next_state = IDLE;
        endcase
    end

    // =========================================================================
    // Cache Controller Datapath (sequential)
    // =========================================================================
    integer k;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            // ---- Reset all cache state ----
            mem_read_en    <= 1'b0;
            mem_write_en   <= 1'b0;
            mem_byte_enable <= 4'b0000;
            mem_addr       <= {ADDR_WIDTH{1'b0}};
            mem_wdata      <= {DATA_WIDTH{1'b0}};
            cpu_rdata      <= {DATA_WIDTH{1'b0}};
            refill_word    <= {OFFSET_WIDTH{1'b0}};
            pending_write  <= 1'b0;
            pending_be     <= 4'b0000;
            pending_wdata  <= {DATA_WIDTH{1'b0}};
            pending_addr   <= {ADDR_WIDTH{1'b0}};
            hit_count        <= 32'd0;
            miss_count       <= 32'd0;
            write_hit_count  <= 32'd0;
            write_miss_count <= 32'd0;
            for (k = 0; k < NUM_SETS; k = k + 1) begin
                valid_array[k] <= 1'b0;
                dirty_array[k] <= 1'b0;
                tag_array[k]   <= {TAG_WIDTH{1'b0}};
            end
        end else begin
            // Default: de-assert memory request signals each cycle
            mem_read_en  <= 1'b0;
            mem_write_en <= 1'b0;

            case (state_reg)
                // ================================================================
                // IDLE: Evaluate incoming CPU request
                // ================================================================
                IDLE: begin
                    if (hit_detect) begin
                        // ---- READ HIT ----
                        if (cpu_read_en) begin
                            cpu_rdata <= data_array[req_index][req_offset];
                            hit_count <= hit_count + 1'b1;
                        end

                        // ---- WRITE HIT ----
                        if (cpu_write_en) begin
                            // Update cache data array with byte masking
                            if (cpu_byte_enable[0]) data_array[req_index][req_offset][7:0]   <= cpu_wdata[7:0];
                            if (cpu_byte_enable[1]) data_array[req_index][req_offset][15:8]  <= cpu_wdata[15:8];
                            if (cpu_byte_enable[2]) data_array[req_index][req_offset][23:16] <= cpu_wdata[23:16];
                            if (cpu_byte_enable[3]) data_array[req_index][req_offset][31:24] <= cpu_wdata[31:24];
                            dirty_array[req_index] <= 1'b1;
                            write_hit_count <= write_hit_count + 1'b1;
                            hit_count       <= hit_count + 1'b1;
                            // Initiate write-through to memory
                            mem_write_en    <= 1'b1;
                            mem_byte_enable <= cpu_byte_enable;
                            mem_addr        <= {cpu_addr[ADDR_WIDTH-1:2], 2'b00};
                            mem_wdata       <= cpu_wdata;
                        end
                    end else if (miss_detect) begin
                        // ---- MISS: begin burst refill from base of cache line ----
                        miss_count  <= miss_count + 1'b1;
                        refill_word <= {OFFSET_WIDTH{1'b0}};
                        // Issue first read request (word 0 of the line)
                        mem_read_en  <= 1'b1;
                        mem_byte_enable <= 4'b1111;
                        mem_addr     <= {cpu_addr[ADDR_WIDTH-1:4], 4'b0000}; // line-aligned
                        // Remember original write info if this is a write-miss
                        if (cpu_write_en) begin
                            pending_write <= 1'b1;
                            pending_be    <= cpu_byte_enable;
                            pending_wdata <= cpu_wdata;
                            pending_addr  <= cpu_addr;
                            write_miss_count <= write_miss_count + 1'b1;
                        end else begin
                            pending_write <= 1'b0;
                        end
                    end
                end

                // ================================================================
                // REFILL: Burst-load 4 words from unified memory into cache line
                // ================================================================
                REFILL: begin
                    if (mem_ready) begin
                        // Store the returned word into the correct slot in the data array
                        data_array[req_index][refill_word] <= mem_rdata;

                        if (refill_word == WORDS_PER_LINE - 1) begin
                            // Final word of burst — commit tag and valid
                            tag_array[req_index]   <= req_tag;
                            valid_array[req_index] <= 1'b1;
                            dirty_array[req_index] <= 1'b0;
                            mem_read_en            <= 1'b0;

                            // Service pending write-miss: apply pending write to cache
                            if (pending_write) begin
                                // Apply byte masking to the target word
                                if (pending_be[0]) data_array[req_index][pending_addr[3:2]][7:0]   <= pending_wdata[7:0];
                                if (pending_be[1]) data_array[req_index][pending_addr[3:2]][15:8]  <= pending_wdata[15:8];
                                if (pending_be[2]) data_array[req_index][pending_addr[3:2]][23:16] <= pending_wdata[23:16];
                                if (pending_be[3]) data_array[req_index][pending_addr[3:2]][31:24] <= pending_wdata[31:24];
                                dirty_array[req_index] <= 1'b1;
                                // Trigger write-through to memory
                                mem_write_en    <= 1'b1;
                                mem_byte_enable <= pending_be;
                                mem_addr        <= {pending_addr[ADDR_WIDTH-1:2], 2'b00};
                                mem_wdata       <= pending_wdata;
                                pending_write   <= 1'b0;
                            end else begin
                                // Read-miss resolved: return the requested word to CPU
                                cpu_rdata <= mem_rdata; // last word might be req_offset==3; handled below
                            end
                        end else begin
                            // Advance to next word in burst
                            refill_word  <= refill_word + 1'b1;
                            mem_read_en  <= 1'b1;
                            mem_byte_enable <= 4'b1111;
                            mem_addr     <= {cpu_addr[ADDR_WIDTH-1:4], refill_word + 1'b1, 2'b00};
                        end
                    end else begin
                        // Keep memory read asserted while waiting
                        mem_read_en     <= 1'b1;
                        mem_byte_enable <= 4'b1111;
                    end
                end

                // ================================================================
                // WTHROUGH: Hold write-through request until memory accepts it
                // ================================================================
                WTHROUGH: begin
                    if (mem_ready) begin
                        mem_write_en <= 1'b0;
                    end else begin
                        mem_write_en    <= 1'b1;
                        // mem_addr and mem_wdata are already latched from IDLE/REFILL
                    end
                end

                default: begin
                    mem_read_en  <= 1'b0;
                    mem_write_en <= 1'b0;
                end
            endcase
        end
    end

    // =========================================================================
    // Read-Hit Data Forwarding (combinational, to remove one-cycle latency
    // on read hits so the CPU sees data the same cycle it asserts cpu_read_en)
    // =========================================================================
    always @(*) begin
        if (state_reg == IDLE && hit_detect && cpu_read_en) begin
            cpu_rdata = data_array[req_index][req_offset];
        end else begin
            cpu_rdata = cpu_rdata; // hold registered value
        end
    end

endmodule
