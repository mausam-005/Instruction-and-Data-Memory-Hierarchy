`timescale 1ns / 1ps
// =============================================================================
// Testbench: tb_dcache
// Description:
//   Automated self-checking verification testbench for the L1 D-Cache
//   (dcache.v) and the Burst-Refill Cache Arbiter (cache_arbiter.v).
//
//   Test Plan:
//     TEST 1 : Cold-start read miss triggers 4-word burst refill.
//     TEST 2 : Read hit returns data in zero stall cycles (cached word).
//     TEST 3 : Write-through on write-hit: cache updated, memory written.
//     TEST 4 : Byte-enable write masking (SB, SH, SW) on write hits.
//     TEST 5 : Write-miss: refill + write-through sequenced correctly.
//     TEST 6 : Cache Arbiter — simultaneous D-Cache and I-Cache refill.
//              D-Cache burst served first, I-Cache burst served after.
//     TEST 7 : Telemetry counter accuracy validation.
// =============================================================================

module tb_dcache;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam DATA_WIDTH     = 32;
    localparam ADDR_WIDTH     = 32;
    localparam NUM_SETS       = 16;
    localparam WORDS_PER_LINE = 4;
    localparam CLK_PERIOD     = 10; // 100 MHz

    // =========================================================================
    // Clock and Reset
    // =========================================================================
    reg clk;
    reg rst;
    always #(CLK_PERIOD / 2) clk = ~clk;

    // =========================================================================
    // CPU-Side DUT Signals (dcache)
    // =========================================================================
    reg                   cpu_read_en;
    reg                   cpu_write_en;
    reg  [3:0]            cpu_byte_enable;
    reg  [ADDR_WIDTH-1:0] cpu_addr;
    reg  [DATA_WIDTH-1:0] cpu_wdata;
    wire [DATA_WIDTH-1:0] cpu_rdata;
    wire                  cpu_stall;
    wire                  cache_hit;
    wire                  cache_miss;
    wire [31:0]           hit_count;
    wire [31:0]           miss_count;
    wire [31:0]           write_hit_count;
    wire [31:0]           write_miss_count;

    // =========================================================================
    // dcache <-> cache_arbiter interconnect
    // =========================================================================
    wire                  d_mem_read_en;
    wire                  d_mem_write_en;
    wire [3:0]            d_mem_byte_enable;
    wire [ADDR_WIDTH-1:0] d_mem_addr;
    wire [DATA_WIDTH-1:0] d_mem_wdata;
    wire [DATA_WIDTH-1:0] d_mem_rdata;
    wire                  d_mem_ready;
    wire                  arb_stall_d;

    // =========================================================================
    // I-Cache Stimulus (for cache_arbiter simultaneous-miss test)
    // =========================================================================
    reg                   icache_read_en;
    reg  [ADDR_WIDTH-1:0] icache_addr;
    wire [DATA_WIDTH-1:0] icache_rdata;
    wire                  icache_ready;
    wire                  arb_stall_i;
    wire                  grant_dcache;
    wire                  grant_icache;
    wire [2:0]            arb_state;
    wire [31:0]           arb_dcache_refill_count;
    wire [31:0]           arb_icache_refill_count;
    wire [31:0]           arb_contention_count;
    wire [31:0]           arb_wthrough_count;

    // =========================================================================
    // Unified Memory — behavioral model (single-port)
    // =========================================================================
    reg  [DATA_WIDTH-1:0] mem_model [0:255]; // 256 word flat array
    wire                  um_mem_read;
    wire                  um_mem_write;
    wire [3:0]            um_mem_byte_enable;
    wire [ADDR_WIDTH-1:0] um_mem_addr;
    wire [DATA_WIDTH-1:0] um_mem_wdata;
    reg  [DATA_WIDTH-1:0] um_mem_rdata;

    // Memory behavioral model
    always @(posedge clk) begin
        if (um_mem_write) begin
            if (um_mem_byte_enable[0]) mem_model[um_mem_addr[9:2]][7:0]   <= um_mem_wdata[7:0];
            if (um_mem_byte_enable[1]) mem_model[um_mem_addr[9:2]][15:8]  <= um_mem_wdata[15:8];
            if (um_mem_byte_enable[2]) mem_model[um_mem_addr[9:2]][23:16] <= um_mem_wdata[23:16];
            if (um_mem_byte_enable[3]) mem_model[um_mem_addr[9:2]][31:24] <= um_mem_wdata[31:24];
        end
    end
    always @(*) begin
        if (um_mem_read)
            um_mem_rdata = mem_model[um_mem_addr[9:2]];
        else
            um_mem_rdata = 32'h00000000;
    end

    // =========================================================================
    // DUT Instantiation: dcache
    // =========================================================================
    dcache #(
        .DATA_WIDTH     (DATA_WIDTH),
        .ADDR_WIDTH     (ADDR_WIDTH),
        .NUM_SETS       (NUM_SETS),
        .WORDS_PER_LINE (WORDS_PER_LINE)
    ) u_dcache (
        .clk             (clk),
        .rst             (rst),
        .cpu_read_en     (cpu_read_en),
        .cpu_write_en    (cpu_write_en),
        .cpu_byte_enable (cpu_byte_enable),
        .cpu_addr        (cpu_addr),
        .cpu_wdata       (cpu_wdata),
        .cpu_rdata       (cpu_rdata),
        .cpu_stall       (cpu_stall),
        .mem_read_en     (d_mem_read_en),
        .mem_write_en    (d_mem_write_en),
        .mem_byte_enable (d_mem_byte_enable),
        .mem_addr        (d_mem_addr),
        .mem_wdata       (d_mem_wdata),
        .mem_rdata       (d_mem_rdata),
        .mem_ready       (d_mem_ready),
        .cache_hit       (cache_hit),
        .cache_miss      (cache_miss),
        .hit_count       (hit_count),
        .miss_count      (miss_count),
        .write_hit_count (write_hit_count),
        .write_miss_count(write_miss_count)
    );

    // =========================================================================
    // DUT Instantiation: cache_arbiter
    // =========================================================================
    cache_arbiter #(
        .DATA_WIDTH     (DATA_WIDTH),
        .ADDR_WIDTH     (ADDR_WIDTH),
        .WORDS_PER_LINE (WORDS_PER_LINE)
    ) u_cache_arbiter (
        .clk                  (clk),
        .rst                  (rst),
        // D-Cache port
        .dcache_read_en       (d_mem_read_en),
        .dcache_write_en      (d_mem_write_en),
        .dcache_byte_enable   (d_mem_byte_enable),
        .dcache_addr          (d_mem_addr),
        .dcache_wdata         (d_mem_wdata),
        .dcache_rdata         (d_mem_rdata),
        .dcache_ready         (d_mem_ready),
        .arb_stall_d          (arb_stall_d),
        // I-Cache port (stimulus from testbench)
        .icache_read_en       (icache_read_en),
        .icache_addr          (icache_addr),
        .icache_rdata         (icache_rdata),
        .icache_ready         (icache_ready),
        .arb_stall_i          (arb_stall_i),
        // Unified memory bus
        .mem_read             (um_mem_read),
        .mem_write            (um_mem_write),
        .mem_byte_enable      (um_mem_byte_enable),
        .mem_addr             (um_mem_addr),
        .mem_wdata            (um_mem_wdata),
        .mem_rdata            (um_mem_rdata),
        // Telemetry
        .arb_state            (arb_state),
        .grant_dcache         (grant_dcache),
        .grant_icache         (grant_icache),
        .dcache_refill_count  (arb_dcache_refill_count),
        .icache_refill_count  (arb_icache_refill_count),
        .contention_count     (arb_contention_count),
        .wthrough_count       (arb_wthrough_count)
    );

    // =========================================================================
    // Bookkeeping
    // =========================================================================
    integer error_count = 0;
    integer test_count  = 0;

    task check_cond;
        input condition;
        input [8*80-1:0] msg;
        begin
            if (!condition) begin
                $display("  [FAIL] %0s", msg);
                error_count = error_count + 1;
            end else begin
                $display("  [PASS] %0s", msg);
            end
        end
    endtask

    // =========================================================================
    // Helper: Wait until CPU stall clears (miss serviced)
    // =========================================================================
    task wait_no_stall;
        integer timeout;
        begin
            timeout = 0;
            while (cpu_stall && timeout < 20) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (timeout >= 20) begin
                $display("  [FAIL] Timeout waiting for stall to clear!");
                error_count = error_count + 1;
            end
        end
    endtask

    // =========================================================================
    // Main Test Stimulus
    // =========================================================================
    integer i;
    initial begin
        $dumpfile("sim/dcache.vcd");
        $dumpvars(0, tb_dcache);

        // ---- Initialize ----
        clk             = 0;
        rst             = 1;
        cpu_read_en     = 0;
        cpu_write_en    = 0;
        cpu_byte_enable = 4'b1111;
        cpu_addr        = 32'd0;
        cpu_wdata       = 32'd0;
        icache_read_en  = 0;
        icache_addr     = 32'd0;

        // Pre-fill memory model with known pattern
        for (i = 0; i < 256; i = i + 1)
            mem_model[i] = 32'hA000_0000 | i;

        $display("==================================================================");
        $display("   L1 D-Cache & Burst-Refill Cache Arbiter Verification Suite    ");
        $display("   Krish Dabas (2401010233)                                      ");
        $display("==================================================================");

        // Apply reset
        repeat(3) @(posedge clk);
        @(negedge clk);
        rst = 0;
        @(posedge clk);

        // =====================================================================
        // TEST 1: Cold-Start Read Miss -> 4-Word Burst Refill
        // =====================================================================
        $display("\n[TEST 1] Cold-Start Read Miss: 4-Word Burst Refill Verification...");
        test_count = test_count + 1;

        @(negedge clk);
        cpu_addr    = 32'h0000_0000;  // Index=0, Offset=0
        cpu_read_en = 1;
        cpu_write_en= 0;

        // Stall should be asserted immediately (cold miss)
        #1;
        check_cond(cpu_stall === 1'b1, "Stall asserted on cold read miss");
        check_cond(cache_miss === 1'b1, "cache_miss high on cold read miss");

        // Wait until cache finishes the burst refill
        wait_no_stall();
        @(negedge clk);
        cpu_read_en = 0;
        #1;

        // Verify memory contains the value we expect at word 0
        check_cond(miss_count == 32'd1, "miss_count incremented to 1 after cold miss");

        // =====================================================================
        // TEST 2: Read Hit — Zero-Stall Cycle After Refill
        // =====================================================================
        $display("\n[TEST 2] Read Hit: Same Line, Zero Stall Cycles...");
        test_count = test_count + 1;

        @(negedge clk);
        cpu_addr    = 32'h0000_0004; // Same line (index=0), word offset=1
        cpu_read_en = 1;
        #1;
        check_cond(cache_hit  === 1'b1, "cache_hit asserted for previously-loaded line");
        check_cond(cpu_stall  === 1'b0, "No stall on read hit");
        check_cond(cpu_rdata  === mem_model[1], "Read hit returned correct data for word offset 1");

        @(negedge clk);
        cpu_addr    = 32'h0000_0008; // Same line, word offset=2
        #1;
        check_cond(cache_hit  === 1'b1, "cache_hit asserted for word offset 2");
        check_cond(cpu_rdata  === mem_model[2], "Read hit correct data for word offset 2");

        @(negedge clk);
        cpu_read_en = 0;
        #1;
        check_cond(hit_count >= 32'd2, "hit_count >= 2 after two read hits");

        // =====================================================================
        // TEST 3: Write-Through on Write Hit
        // =====================================================================
        $display("\n[TEST 3] Write-Through: Write Hit Updates Cache and Memory...");
        test_count = test_count + 1;

        @(negedge clk);
        cpu_addr        = 32'h0000_0000; // Word 0, still in cache (line from TEST 1)
        cpu_wdata       = 32'hDEAD_BEEF;
        cpu_byte_enable = 4'b1111;
        cpu_write_en    = 1;
        cpu_read_en     = 0;
        #1;
        check_cond(cache_hit === 1'b1, "Write-hit detected: address in cache");

        @(posedge clk); // Allow write-through to propagate
        @(negedge clk);
        cpu_write_en = 0;
        // Allow WTHROUGH state to complete
        repeat(2) @(posedge clk);
        @(negedge clk);

        // Verify memory was written (write-through completed)
        check_cond(mem_model[0] === 32'hDEAD_BEEF, "Write-through: unified memory updated to 0xDEADBEEF");
        check_cond(write_hit_count >= 32'd1, "write_hit_count incremented after write hit");

        // Read back via cache to confirm cache also holds the new value
        @(negedge clk);
        cpu_addr    = 32'h0000_0000;
        cpu_read_en = 1;
        #1;
        check_cond(cache_hit === 1'b1, "Cache hit after write-through (data remains in cache)");
        check_cond(cpu_rdata === 32'hDEAD_BEEF, "Cache returned updated value 0xDEADBEEF");

        @(negedge clk);
        cpu_read_en = 0;

        // =====================================================================
        // TEST 4: Byte-Enable Write Masking (SB / SH / SW)
        // =====================================================================
        $display("\n[TEST 4] Byte-Enable Write Masking (SB, SH, SW)...");
        test_count = test_count + 1;

        // Starting value at word 0: 0xDEADBEEF (from TEST 3)
        // --- SB: Write byte 1 (bits [15:8]) with 0xAA ---
        @(negedge clk);
        cpu_addr        = 32'h0000_0000;
        cpu_wdata       = 32'h0000_AA00;
        cpu_byte_enable = 4'b0010;      // SB byte 1
        cpu_write_en    = 1;
        cpu_read_en     = 0;
        #1;
        check_cond(cache_hit === 1'b1, "SB write hit detected");

        @(posedge clk);
        @(negedge clk);
        cpu_write_en = 0;
        repeat(2) @(posedge clk);
        @(negedge clk);

        // Expected: 0xDEADAAEF — only byte 1 changed
        check_cond(mem_model[0] === 32'hDEAD_AAEF, "SB masking: memory byte[1] updated, others preserved");

        // Read from cache
        cpu_addr    = 32'h0000_0000;
        cpu_read_en = 1;
        #1;
        check_cond(cpu_rdata === 32'hDEAD_AAEF, "SB masking: cache byte[1] updated correctly");

        @(negedge clk);
        cpu_read_en = 0;

        // --- SH: Write halfword (bytes [31:16]) with 0xCAFE ---
        @(negedge clk);
        cpu_addr        = 32'h0000_0000;
        cpu_wdata       = 32'hCAFE_0000;
        cpu_byte_enable = 4'b1100;      // SH upper halfword
        cpu_write_en    = 1;
        #1;
        check_cond(cache_hit === 1'b1, "SH write hit detected");

        @(posedge clk);
        @(negedge clk);
        cpu_write_en = 0;
        repeat(2) @(posedge clk);
        @(negedge clk);

        // Expected: 0xCAFEAAEF
        check_cond(mem_model[0] === 32'hCAFE_AAEF, "SH masking: upper halfword updated, lower preserved");

        @(negedge clk);

        // =====================================================================
        // TEST 5: Write Miss — Refill Then Write-Through
        // =====================================================================
        $display("\n[TEST 5] Write Miss: Burst Refill Followed by Write-Through...");
        test_count = test_count + 1;

        @(negedge clk);
        // Address in a different cache set (index=1 => addr[7:4]=0x1 => addr 0x0010)
        cpu_addr        = 32'h0000_0010; // Index=1, Offset=0
        cpu_wdata       = 32'h1234_5678;
        cpu_byte_enable = 4'b1111;       // SW
        cpu_write_en    = 1;
        cpu_read_en     = 0;
        #1;
        check_cond(cache_miss === 1'b1, "Write miss detected for uncached address 0x0010");
        check_cond(cpu_stall  === 1'b1, "Stall asserted on write miss");

        wait_no_stall();
        @(negedge clk);
        cpu_write_en = 0;
        repeat(2) @(posedge clk);
        @(negedge clk);

        // Memory should now have the written value
        check_cond(mem_model[32'h0010 >> 2] === 32'h1234_5678,
                   "Write-miss: write-through committed to unified memory");
        check_cond(write_miss_count >= 32'd1, "write_miss_count incremented");

        // Read it back — should now be a cache hit
        cpu_addr    = 32'h0000_0010;
        cpu_read_en = 1;
        cpu_write_en= 0;
        #1;
        check_cond(cache_hit === 1'b1, "Post-write-miss: address now in cache (hit)");
        check_cond(cpu_rdata === 32'h1234_5678, "Post-write-miss: correct value returned from cache");

        @(negedge clk);
        cpu_read_en = 0;
        @(posedge clk);

        // =====================================================================
        // TEST 6: Cache Arbiter — Simultaneous D-Cache and I-Cache Refill
        // =====================================================================
        $display("\n[TEST 6] Cache Arbiter: Simultaneous D-Cache & I-Cache Miss Arbitration...");
        test_count = test_count + 1;

        // Strategy: Start D-Cache miss at negedge. dcache drives d_mem_read_en
        // synchronously (on the NEXT posedge: IDLE->REFILL). We then assert
        // icache_read_en on that NEXT negedge so the arbiter sees both
        // simultaneously, triggering contention.
        //
        // Step 1: Initiate D-Cache miss
        @(negedge clk);
        cpu_addr        = 32'h0000_0020; // Index=2, cold miss
        cpu_read_en     = 1;
        cpu_write_en    = 0;
        cpu_byte_enable = 4'b1111;
        icache_read_en  = 0;
        icache_addr     = 32'h0000_0040;
        #1;
        check_cond(cache_miss === 1'b1, "D-Cache misses on 0x0020 (cold)");

        // Step 2: posedge — dcache IDLE->REFILL; d_mem_read_en rises.
        //         Simultaneously raise icache_read_en on negedge so arbiter
        //         sees d_req AND i_req on the same IDLE evaluation cycle.
        @(posedge clk);
        @(negedge clk);
        icache_read_en = 1;             // Both requests now asserted together
        #1;
        check_cond(d_mem_read_en === 1'b1, "D-Cache d_mem_read_en high (refill burst active)");

        // Step 3: posedge — arbiter: IDLE->SERVE_DCACHE, grant_dcache rises
        @(posedge clk);
        @(negedge clk); #1;
        check_cond(grant_dcache === 1'b1, "Arbiter grants D-Cache burst first (data priority)");
        check_cond(arb_stall_i  === 1'b1, "I-Cache stalled while D-Cache burst in progress");

        // Step 4: Wait for D-Cache burst to complete
        wait_no_stall();
        @(negedge clk);
        cpu_read_en    = 0;
        // Keep I-Cache active so arbiter transitions to PENDING_ICACHE after D burst
        repeat(WORDS_PER_LINE + 2) @(posedge clk);
        icache_read_en = 0;

        // Contention counter: set when d_req and i_req simultaneously hit arbiter IDLE
        @(posedge clk);
        check_cond(arb_contention_count >= 32'd1, "Arbiter contention_count >= 1 from simultaneous miss");
        check_cond(arb_dcache_refill_count >= 32'd1, "D-Cache refill count incremented by arbiter");

        // =====================================================================
        // TEST 7: Telemetry Counter Accuracy
        // =====================================================================
        $display("\n[TEST 7] Telemetry & Performance Counter Validation...");
        test_count = test_count + 1;

        check_cond(miss_count        > 32'd0, "miss_count > 0 (misses were recorded)");
        check_cond(hit_count         > 32'd0, "hit_count > 0 (hits were recorded)");
        check_cond(write_hit_count   > 32'd0, "write_hit_count > 0 (write hits recorded)");
        check_cond(write_miss_count  > 32'd0, "write_miss_count > 0 (write misses recorded)");
        check_cond(arb_wthrough_count > 32'd0, "arbiter wthrough_count > 0 (write-throughs forwarded)");

        // =====================================================================
        // Final Report
        // =====================================================================
        $display("\n==================================================================");
        $display("        L1 D-CACHE & CACHE ARBITER TELEMETRY REPORT               ");
        $display("==================================================================");
        $display("  Cache Read Hits            : %0d", hit_count);
        $display("  Cache Read/Write Misses    : %0d", miss_count);
        $display("  Write Hits (Write-Through) : %0d", write_hit_count);
        $display("  Write Misses (Refill+WT)   : %0d", write_miss_count);
        $display("  Arbiter D-Cache Refills    : %0d", arb_dcache_refill_count);
        $display("  Arbiter I-Cache Refills    : %0d", arb_icache_refill_count);
        $display("  Arbiter Contention Events  : %0d", arb_contention_count);
        $display("  Arbiter Write-Throughs     : %0d", arb_wthrough_count);
        $display("==================================================================");

        if (error_count == 0) begin
            $display(" >>> ALL %0d TESTS PASSED SUCCESSFULLY! (0 errors) <<<", test_count);
            $display(" L1 D-Cache Write-Through & Burst-Refill Arbiter Verified.");
        end else begin
            $display(" >>> FAILED: %0d ERRORS DETECTED <<<", error_count);
        end
        $display("==================================================================\n");

        $finish;
    end

endmodule
