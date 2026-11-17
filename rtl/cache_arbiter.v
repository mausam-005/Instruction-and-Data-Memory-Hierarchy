`timescale 1ns / 1ps
// =============================================================================
// Module: cache_arbiter
// Description:
//   Burst-Refill Cache Bus Arbiter for the L1 Harvard Cache Hierarchy.
//
//   This arbiter sits between the I-Cache / D-Cache and the shared backing
//   unified memory (unified_mem.v).  When both caches simultaneously miss and
//   issue refill requests in the same clock cycle, this arbiter serializes the
//   burst refill sequences so that:
//     1. The D-Cache refill is served first (data-priority policy, matching
//        the existing Von Neumann mem_arbiter philosophy).
//     2. The I-Cache refill is deferred and served immediately after.
//
//   Burst Operation:
//     Each cache line = 4 words.  A refill burst is 4 consecutive single-word
//     reads from the unified memory.  The arbiter keeps the granted port's burst
//     active across all 4 words before switching to the other port.
//
//   FSM States:
//     IDLE             (3'b000) : No pending refill requests.
//     SERVE_DCACHE     (3'b001) : Burst-serving D-Cache refill words.
//     SERVE_ICACHE     (3'b010) : Burst-serving I-Cache refill words.
//     DCACHE_WTHROUGH  (3'b011) : Forwarding a D-Cache write-through to memory.
//     PENDING_ICACHE   (3'b100) : D-Cache burst done; I-Cache burst pending.
//     PENDING_DCACHE   (3'b101) : I-Cache burst done; D-Cache burst pending.
//
//   Grant Signals:
//     grant_dcache : D-Cache has exclusive bus access this cycle.
//     grant_icache : I-Cache has exclusive bus access this cycle.
//     arb_stall_d  : D-Cache must hold its refill request; arbiter is busy.
//     arb_stall_i  : I-Cache must hold its refill request; arbiter is busy.
// =============================================================================

module cache_arbiter #(
    parameter DATA_WIDTH     = 32,
    parameter ADDR_WIDTH     = 32,
    parameter WORDS_PER_LINE = 4           // Burst depth = one full cache line
)(
    input  wire                  clk,
    input  wire                  rst,

    // -------------------------------------------------------------------------
    // D-Cache Port (higher priority)
    // -------------------------------------------------------------------------
    input  wire                  dcache_read_en,     // D-Cache requests a refill read
    input  wire                  dcache_write_en,    // D-Cache write-through request
    input  wire [3:0]            dcache_byte_enable,
    input  wire [ADDR_WIDTH-1:0] dcache_addr,
    input  wire [DATA_WIDTH-1:0] dcache_wdata,
    output wire [DATA_WIDTH-1:0] dcache_rdata,       // Refill word returned to D-Cache
    output wire                  dcache_ready,       // Word is ready / write accepted
    output wire                  arb_stall_d,        // D-Cache must wait

    // -------------------------------------------------------------------------
    // I-Cache Port (lower priority)
    // -------------------------------------------------------------------------
    input  wire                  icache_read_en,     // I-Cache requests a refill read
    input  wire [ADDR_WIDTH-1:0] icache_addr,
    output wire [DATA_WIDTH-1:0] icache_rdata,       // Refill word returned to I-Cache
    output wire                  icache_ready,       // Word is ready
    output wire                  arb_stall_i,        // I-Cache must wait

    // -------------------------------------------------------------------------
    // Unified Memory Port (single-port backing store)
    // -------------------------------------------------------------------------
    output wire                  mem_read,
    output wire                  mem_write,
    output wire [3:0]            mem_byte_enable,
    output wire [ADDR_WIDTH-1:0] mem_addr,
    output wire [DATA_WIDTH-1:0] mem_wdata,
    input  wire [DATA_WIDTH-1:0] mem_rdata,

    // -------------------------------------------------------------------------
    // Arbiter Status & Telemetry
    // -------------------------------------------------------------------------
    output wire [2:0]            arb_state,
    output wire                  grant_dcache,
    output wire                  grant_icache,
    output reg  [31:0]           dcache_refill_count,
    output reg  [31:0]           icache_refill_count,
    output reg  [31:0]           contention_count,
    output reg  [31:0]           wthrough_count
);

    // =========================================================================
    // FSM State Encoding
    // =========================================================================
    localparam [2:0] IDLE            = 3'b000;
    localparam [2:0] SERVE_DCACHE    = 3'b001;
    localparam [2:0] SERVE_ICACHE    = 3'b010;
    localparam [2:0] DCACHE_WTHROUGH = 3'b011;
    localparam [2:0] PENDING_ICACHE  = 3'b100;
    localparam [2:0] PENDING_DCACHE  = 3'b101;

    reg [2:0] state_reg, next_state;

    // =========================================================================
    // Burst Word Counter
    // =========================================================================
    // Counts how many words of the current burst have been issued.
    // Memory is assumed single-cycle ready (ready = 1 always after one cycle).
    // mem_ready is registered from mem_rdata availability.
    reg [$clog2(WORDS_PER_LINE)-1:0] burst_cnt;

    // =========================================================================
    // Internal Address Tracking
    // =========================================================================
    // We latch the base address of the winning cache's line at burst start
    // so the arbiter autonomously generates sequential word addresses.
    reg [ADDR_WIDTH-1:0] dcache_base_latch;
    reg [ADDR_WIDTH-1:0] icache_base_latch;

    // Convenience wires
    wire d_req  = dcache_read_en | dcache_write_en;
    wire i_req  = icache_read_en;
    wire d_wt   = dcache_write_en & ~dcache_read_en; // pure write-through, not a refill

    // =========================================================================
    // Synchronous State & Counter Registers
    // =========================================================================
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state_reg           <= IDLE;
            burst_cnt           <= {$clog2(WORDS_PER_LINE){1'b0}};
            dcache_base_latch   <= {ADDR_WIDTH{1'b0}};
            icache_base_latch   <= {ADDR_WIDTH{1'b0}};
            dcache_refill_count <= 32'd0;
            icache_refill_count <= 32'd0;
            contention_count    <= 32'd0;
            wthrough_count      <= 32'd0;
        end else begin
            state_reg <= next_state;

            case (state_reg)
                IDLE: begin
                    if (d_wt && ~dcache_read_en) begin
                        // Write-through (no refill needed, just forward)
                        wthrough_count <= wthrough_count + 1'b1;
                    end else if (d_req && dcache_read_en && i_req) begin
                        // Contention: both caches miss simultaneously
                        contention_count    <= contention_count + 1'b1;
                        dcache_base_latch   <= {dcache_addr[ADDR_WIDTH-1:4], 4'b0000};
                        icache_base_latch   <= {icache_addr[ADDR_WIDTH-1:4], 4'b0000};
                        burst_cnt           <= {$clog2(WORDS_PER_LINE){1'b0}};
                        dcache_refill_count <= dcache_refill_count + 1'b1;
                    end else if (d_req) begin
                        dcache_base_latch   <= {dcache_addr[ADDR_WIDTH-1:4], 4'b0000};
                        burst_cnt           <= {$clog2(WORDS_PER_LINE){1'b0}};
                        if (dcache_read_en) dcache_refill_count <= dcache_refill_count + 1'b1;
                        if (d_wt)           wthrough_count      <= wthrough_count + 1'b1;
                    end else if (i_req) begin
                        icache_base_latch   <= {icache_addr[ADDR_WIDTH-1:4], 4'b0000};
                        burst_cnt           <= {$clog2(WORDS_PER_LINE){1'b0}};
                        icache_refill_count <= icache_refill_count + 1'b1;
                    end
                end

                SERVE_DCACHE: begin
                    // Count up each cycle (memory is 1-cycle latency, always ready next cycle)
                    if (burst_cnt < WORDS_PER_LINE - 1) begin
                        burst_cnt <= burst_cnt + 1'b1;
                        // Detect I-Cache arriving while D-Cache burst is in progress
                        if (i_req && burst_cnt == {$clog2(WORDS_PER_LINE){1'b0}}) begin
                            contention_count  <= contention_count + 1'b1;
                            icache_base_latch <= {icache_addr[ADDR_WIDTH-1:4], 4'b0000};
                        end
                    end else begin
                        // Burst complete. If I-Cache was waiting, latch its address now.
                        burst_cnt <= {$clog2(WORDS_PER_LINE){1'b0}};
                        if (i_req && icache_base_latch == {ADDR_WIDTH{1'b0}}) begin
                            icache_base_latch   <= {icache_addr[ADDR_WIDTH-1:4], 4'b0000};
                            icache_refill_count <= icache_refill_count + 1'b1;
                        end else if (icache_base_latch != {ADDR_WIDTH{1'b0}}) begin
                            icache_refill_count <= icache_refill_count + 1'b1;
                        end
                    end
                end

                SERVE_ICACHE: begin
                    if (burst_cnt < WORDS_PER_LINE - 1) begin
                        burst_cnt <= burst_cnt + 1'b1;
                    end else begin
                        burst_cnt <= {$clog2(WORDS_PER_LINE){1'b0}};
                        if (d_req) begin
                            dcache_base_latch   <= {dcache_addr[ADDR_WIDTH-1:4], 4'b0000};
                            dcache_refill_count <= dcache_refill_count + 1'b1;
                        end
                    end
                end

                DCACHE_WTHROUGH: begin
                    wthrough_count <= wthrough_count; // already counted in IDLE
                end

                PENDING_ICACHE: begin
                    if (burst_cnt < WORDS_PER_LINE - 1) begin
                        burst_cnt <= burst_cnt + 1'b1;
                    end else begin
                        burst_cnt <= {$clog2(WORDS_PER_LINE){1'b0}};
                    end
                end

                PENDING_DCACHE: begin
                    if (burst_cnt < WORDS_PER_LINE - 1) begin
                        burst_cnt <= burst_cnt + 1'b1;
                    end else begin
                        burst_cnt <= {$clog2(WORDS_PER_LINE){1'b0}};
                    end
                end

                default: begin
                    burst_cnt <= {$clog2(WORDS_PER_LINE){1'b0}};
                end
            endcase
        end
    end

    // =========================================================================
    // Next-State Combinational Logic
    // =========================================================================
    always @(*) begin
        next_state = state_reg;
        case (state_reg)
            IDLE: begin
                if (d_wt && ~dcache_read_en) begin
                    next_state = DCACHE_WTHROUGH;
                end else if (d_req && dcache_read_en && i_req) begin
                    // Both miss: serve D-Cache first, then I-Cache
                    next_state = SERVE_DCACHE;
                end else if (d_req && dcache_read_en) begin
                    next_state = SERVE_DCACHE;
                end else if (i_req) begin
                    next_state = SERVE_ICACHE;
                end else begin
                    next_state = IDLE;
                end
            end

            SERVE_DCACHE: begin
                if (burst_cnt == WORDS_PER_LINE - 1) begin
                    // Check if I-Cache was also pending (came from contention)
                    if (icache_base_latch != {ADDR_WIDTH{1'b0}} || i_req) begin
                        next_state = PENDING_ICACHE;
                    end else begin
                        next_state = IDLE;
                    end
                end else begin
                    next_state = SERVE_DCACHE;
                end
            end

            SERVE_ICACHE: begin
                if (burst_cnt == WORDS_PER_LINE - 1) begin
                    if (dcache_base_latch != {ADDR_WIDTH{1'b0}} || d_req) begin
                        next_state = PENDING_DCACHE;
                    end else begin
                        next_state = IDLE;
                    end
                end else begin
                    next_state = SERVE_ICACHE;
                end
            end

            DCACHE_WTHROUGH: begin
                // Single-cycle write-through
                next_state = IDLE;
            end

            PENDING_ICACHE: begin
                // Burst-serving the I-Cache after D-Cache burst completed
                if (burst_cnt == WORDS_PER_LINE - 1) begin
                    next_state = IDLE;
                end else begin
                    next_state = PENDING_ICACHE;
                end
            end

            PENDING_DCACHE: begin
                // Burst-serving the D-Cache after I-Cache burst completed
                if (burst_cnt == WORDS_PER_LINE - 1) begin
                    next_state = IDLE;
                end else begin
                    next_state = PENDING_DCACHE;
                end
            end

            default: next_state = IDLE;
        endcase
    end

    // =========================================================================
    // Grant Signals (combinational from state)
    // =========================================================================
    assign grant_dcache = (state_reg == SERVE_DCACHE)   ||
                          (state_reg == DCACHE_WTHROUGH) ||
                          (state_reg == PENDING_DCACHE);
    assign grant_icache = (state_reg == SERVE_ICACHE)  ||
                          (state_reg == PENDING_ICACHE);

    assign arb_stall_d  = (state_reg == SERVE_ICACHE)  ||
                          (state_reg == PENDING_ICACHE) ||
                          (state_reg == SERVE_DCACHE && dcache_read_en && burst_cnt != WORDS_PER_LINE-1);
    assign arb_stall_i  = (state_reg == SERVE_DCACHE)   ||
                          (state_reg == DCACHE_WTHROUGH) ||
                          (state_reg == PENDING_DCACHE);

    // =========================================================================
    // Memory Bus Mux — routes the winning cache's current burst word address
    // =========================================================================
    wire [ADDR_WIDTH-1:0] dcache_burst_addr = dcache_base_latch | {{(ADDR_WIDTH-4){1'b0}}, burst_cnt, 2'b00};
    wire [ADDR_WIDTH-1:0] icache_burst_addr = icache_base_latch | {{(ADDR_WIDTH-4){1'b0}}, burst_cnt, 2'b00};

    assign mem_read = (state_reg == SERVE_DCACHE)   && dcache_read_en   ||
                      (state_reg == SERVE_ICACHE)   && icache_read_en   ||
                      (state_reg == PENDING_ICACHE)                     ||
                      (state_reg == PENDING_DCACHE);
    assign mem_write        = (state_reg == DCACHE_WTHROUGH) ? 1'b1 : 1'b0;
    assign mem_byte_enable  = (state_reg == DCACHE_WTHROUGH) ? dcache_byte_enable : 4'b1111;

    assign mem_addr  = (state_reg == SERVE_DCACHE   || state_reg == PENDING_DCACHE) ? dcache_burst_addr :
                       (state_reg == SERVE_ICACHE   || state_reg == PENDING_ICACHE) ? icache_burst_addr :
                       (state_reg == DCACHE_WTHROUGH)                               ? dcache_addr       :
                                                                                      {ADDR_WIDTH{1'b0}};

    assign mem_wdata = dcache_wdata;

    // =========================================================================
    // Data Routing — mem_rdata returned to the correct cache
    // =========================================================================
    assign dcache_rdata  = mem_rdata;
    assign icache_rdata  = mem_rdata;

    // Ready signals: combinational — valid the cycle after a read is issued
    assign dcache_ready = grant_dcache;
    assign icache_ready = grant_icache;

    assign arb_state    = state_reg;

endmodule
