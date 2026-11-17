// =============================================================================
// Project: Instruction and Data Memory Hierarchy (Phase II)
// Testbench: tb_icache.v
// Author   : Mausam Kumar Dwivedi (Role 1: Lead Architect)
// Description: Automated self-checking verification testbench for L1 I-Cache.
//              Verifies compulsory miss, burst refill, spatial locality hits,
//              temporal locality hits, line eviction, and hardware telemetry.
// =============================================================================

`timescale 1ns / 1ps

module tb_icache;

    reg         clk;
    reg         rst_n;

    // CPU Port
    reg  [31:0] cpu_addr;
    reg         cpu_req;
    wire [31:0] cpu_rdata;
    wire        cpu_hit;
    wire        cpu_stall;

    // Lower Memory Refill Port
    wire [31:0] mem_addr;
    wire        mem_req;
    reg  [127:0] mem_line_data;
    reg         mem_ready;

    // Telemetry
    wire [31:0] icache_hits;
    wire [31:0] icache_misses;
    wire [31:0] icache_accesses;

    integer test_errors = 0;

    // Instantiate L1 Instruction Cache
    icache uut (
        .clk(clk),
        .rst_n(rst_n),
        .cpu_addr(cpu_addr),
        .cpu_req(cpu_req),
        .cpu_rdata(cpu_rdata),
        .cpu_hit(cpu_hit),
        .cpu_stall(cpu_stall),
        .mem_addr(mem_addr),
        .mem_req(mem_req),
        .mem_line_data(mem_line_data),
        .mem_ready(mem_ready),
        .icache_hits(icache_hits),
        .icache_misses(icache_misses),
        .icache_accesses(icache_accesses)
    );

    // 100 MHz Simulation Clock
    always #5 clk = ~clk;

    // Emulated Backing Memory Responder
    // Simulates a realistic 2-cycle main memory line access
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_ready     <= 1'b0;
            mem_line_data <= 128'h0;
        end else begin
            if (mem_req && !mem_ready) begin
                // Provide synthetic 4-word instruction line based on base address
                mem_line_data <= {
                    mem_addr + 32'h0C, // Word 3
                    mem_addr + 32'h08, // Word 2
                    mem_addr + 32'h04, // Word 1
                    mem_addr + 32'h00  // Word 0
                };
                mem_ready <= 1'b1;
            end else begin
                mem_ready <= 1'b0;
            end
        end
    end

    initial begin
        $dumpfile("sim/icache.vcd");
        $dumpvars(0, tb_icache);

        clk      = 0;
        rst_n    = 0;
        cpu_addr = 32'h0;
        cpu_req  = 0;

        $display("==================================================================");
        $display("    L1 Instruction Cache Self-Checking Verification Testbench    ");
        $display("    Author: Mausam Kumar Dwivedi (Role 1: Lead Architect)        ");
        $display("==================================================================");

        // Reset Pulse
        #20;
        rst_n = 1;
        #10;

        // ---------------------------------------------------------------------
        // TEST 1: Cold / Compulsory Cache Miss (Address 0x00000000)
        // ---------------------------------------------------------------------
        $display("\n[TEST 1] Verifying Compulsory Cold Miss at Addr 0x00...");
        @(negedge clk);
        cpu_addr = 32'h00000000;
        cpu_req  = 1'b1;

        @(posedge clk);
        #1;
        if (cpu_stall !== 1'b1) begin
            $display("  [FAIL] Expected cpu_stall=1 on compulsory miss! Got %b", cpu_stall);
            test_errors = test_errors + 1;
        end else begin
            $display("  [PASS] cpu_stall successfully asserted on cache miss.");
        end

        // Wait until refill completes and stall de-asserts
        wait (cpu_stall == 1'b0);
        #1;
        if (cpu_rdata === 32'h00000000) begin
            $display("  [PASS] Word 0 Refilled & Served Cleanly: 0x%08x", cpu_rdata);
        end else begin
            $display("  [FAIL] Expected 0x00000000, Got: 0x%08x", cpu_rdata);
            test_errors = test_errors + 1;
        end

        // ---------------------------------------------------------------------
        // TEST 2: Spatial Locality Hit within the same 16-byte line
        // Addresses 0x04, 0x08, 0x0C were pre-fetched in line 0!
        // ---------------------------------------------------------------------
        $display("\n[TEST 2] Verifying Spatial Locality (Zero-Stall Cache Hits)...");
        @(negedge clk);
        cpu_addr = 32'h00000004; // Word 1
        cpu_req  = 1'b1;

        @(posedge clk);
        #1;
        if (cpu_hit === 1'b1 && cpu_stall === 1'b0 && cpu_rdata === 32'h00000004) begin
            $display("  [PASS] Addr 0x04: 1-Cycle Zero-Stall Hit! Data = 0x%08x", cpu_rdata);
        end else begin
            $display("  [FAIL] Addr 0x04 hit failed! hit=%b, stall=%b, data=0x%08x", cpu_hit, cpu_stall, cpu_rdata);
            test_errors = test_errors + 1;
        end

        @(negedge clk);
        cpu_addr = 32'h00000008; // Word 2
        @(posedge clk);
        #1;
        if (cpu_hit === 1'b1 && cpu_stall === 1'b0 && cpu_rdata === 32'h00000008) begin
            $display("  [PASS] Addr 0x08: 1-Cycle Zero-Stall Hit! Data = 0x%08x", cpu_rdata);
        end else begin
            $display("  [FAIL] Addr 0x08 hit failed! hit=%b, data=0x%08x", cpu_hit, cpu_rdata);
            test_errors = test_errors + 1;
        end

        @(negedge clk);
        cpu_addr = 32'h0000000C; // Word 3
        @(posedge clk);
        #1;
        if (cpu_hit === 1'b1 && cpu_stall === 1'b0 && cpu_rdata === 32'h0000000C) begin
            $display("  [PASS] Addr 0x0C: 1-Cycle Zero-Stall Hit! Data = 0x%08x", cpu_rdata);
        end else begin
            $display("  [FAIL] Addr 0x0C hit failed! hit=%b, data=0x%08x", cpu_hit, cpu_rdata);
            test_errors = test_errors + 1;
        end

        // ---------------------------------------------------------------------
        // TEST 3: Temporal Locality (Re-fetching Addr 0x00)
        // ---------------------------------------------------------------------
        $display("\n[TEST 3] Verifying Temporal Locality (Re-fetching Addr 0x00)...");
        @(negedge clk);
        cpu_addr = 32'h00000000;
        @(posedge clk);
        #1;
        if (cpu_hit === 1'b1 && cpu_stall === 1'b0 && cpu_rdata === 32'h00000000) begin
            $display("  [PASS] Addr 0x00: Temporal Hit verified! Data = 0x%08x", cpu_rdata);
        end else begin
            $display("  [FAIL] Addr 0x00 temporal hit failed! hit=%b, data=0x%08x", cpu_hit, cpu_rdata);
            test_errors = test_errors + 1;
        end

        // ---------------------------------------------------------------------
        // TEST 4: Cache Conflict & Line Eviction
        // Addr 0x00000080 maps to Line Index 0 (0x80 = 8'b1000_0000 -> Index=0, Tag!=0)
        // Should evict line 0 and refill!
        // ---------------------------------------------------------------------
        $display("\n[TEST 4] Verifying Cache Conflict & Line Eviction at Index 0...");
        @(negedge clk);
        cpu_addr = 32'h00000080; // Line index 0, but different tag!
        @(posedge clk);
        #1;
        if (cpu_stall === 1'b1) begin
            $display("  [PASS] Conflict miss correctly detected; stall asserted.");
        end else begin
            $display("  [FAIL] Expected stall on tag conflict!");
            test_errors = test_errors + 1;
        end

        wait (cpu_stall == 1'b0);
        #1;
        if (cpu_rdata === 32'h00000080) begin
            $display("  [PASS] Line 0 Eviction and New Line Allocation Verified! Data = 0x%08x", cpu_rdata);
        end else begin
            $display("  [FAIL] Expected 0x00000080, Got 0x%08x", cpu_rdata);
            test_errors = test_errors + 1;
        end

        // ---------------------------------------------------------------------
        // TEST 5: Hardware Telemetry Verification
        // ---------------------------------------------------------------------
        $display("\n[TEST 5] Validating Hardware Telemetry Performance Counters...");
        @(negedge clk);
        cpu_req = 1'b0;
        #10;

        $display("==================================================================");
        $display("                   L1 I-CACHE TELEMETRY REPORT                    ");
        $display("==================================================================");
        $display("  Total Cache Accesses : %0d", icache_accesses);
        $display("  Cache Hits           : %0d", icache_hits);
        $display("  Cache Misses         : %0d", icache_misses);
        if (icache_accesses > 0) begin
            $display("  Cache Hit Rate (%%)   : %0.2f %%", (icache_hits * 100.0) / icache_accesses);
        end
        $display("==================================================================");

        if (icache_misses === 32'd2 && icache_hits === 32'd4 && icache_accesses === 32'd6) begin
            $display("  [PASS] All Performance Counters match expected trace!");
        end else begin
            $display("  [FAIL] Counter mismatch! Hits=%0d (exp 4), Misses=%0d (exp 2), Accesses=%0d (exp 6)",
                     icache_hits, icache_misses, icache_accesses);
            test_errors = test_errors + 1;
        end

        if (test_errors == 0) begin
            $display("\n >>> ALL 5 I-CACHE TESTS PASSED SUCCESSFULLY! (0 errors) <<<");
        end else begin
            $display("\n >>> VERIFICATION FAILED WITH %0d ERRORS! <<<", test_errors);
        end
        $display("==================================================================\n");

        $finish;
    end

endmodule
