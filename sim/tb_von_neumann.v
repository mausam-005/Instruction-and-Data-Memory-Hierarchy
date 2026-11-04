`timescale 1ns / 1ps
// =============================================================================
// Testbench: tb_von_neumann
// Project: Instruction and Data Memory Hierarchy
// Role 4: ALU & Verification Specialist (Arun Kumar Giri)
// Description:
//   Automated self-checking verification testbench for the unified Von Neumann
//   memory subsystem (von_neumann_top.v). Validates:
//     1. Conflict-free instruction fetch operations (0 stall penalty).
//     2. Conflict-free data read/write transactions (0 stall penalty).
//     3. Arbiter state transitions and single-cycle stall injection during
//        simultaneous instruction fetch and data memory access (structural hazard).
//     4. Back-to-back contention sequences and bus grant transitions.
//     5. Zero data corruption during concurrent arbitration.
//     6. Line-rate telemetry performance counters (stall_count, cycle_count).
// =============================================================================

module tb_von_neumann;

    // Parameters
    localparam DATA_WIDTH = 32;
    localparam ADDR_WIDTH = 32;
    localparam MEM_DEPTH  = 256;
    localparam CLK_PERIOD = 10; // 100 MHz clock (10 ns period)

    // Clock and Reset
    reg                  clk;
    reg                  rst;

    // Instruction Port (Fetch Path)
    reg                  instr_read_en;
    reg  [ADDR_WIDTH-1:0] instr_addr;
    wire [DATA_WIDTH-1:0] instr_data;

    // Data Port (Load / Store Path)
    reg                  data_read_en;
    reg                  data_write_en;
    reg  [3:0]            data_byte_enable;
    reg  [ADDR_WIDTH-1:0] data_addr;
    reg  [DATA_WIDTH-1:0] data_wdata;
    wire [DATA_WIDTH-1:0] data_rdata;

    // Arbiter & Stall Control Signals
    wire                 stall;
    wire                 grant_instr;
    wire                 grant_data;
    wire [1:0]            arb_state;

    // Telemetry Performance Counters
    wire [31:0]          cycle_count;
    wire [31:0]          stall_count;
    wire [31:0]          contention_count;
    wire [31:0]          total_fetch_count;
    wire [31:0]          total_data_access_count;

    // Verification Bookkeeping
    integer error_count    = 0;
    integer test_count     = 0;
    integer expected_stalls = 0;

    // =========================================================================
    // Device Under Test (DUT) Instantiation
    // =========================================================================
    von_neumann_top #(
        .DATA_WIDTH     (DATA_WIDTH),
        .ADDR_WIDTH     (ADDR_WIDTH),
        .MEM_DEPTH      (MEM_DEPTH),
        .MEM_INIT_FILE  ("benchmarks/sample_prog.mem")
    ) dut (
        .clk                     (clk),
        .rst                     (rst),
        .instr_read_en           (instr_read_en),
        .instr_addr              (instr_addr),
        .instr_data              (instr_data),
        .data_read_en            (data_read_en),
        .data_write_en           (data_write_en),
        .data_byte_enable        (data_byte_enable),
        .data_addr               (data_addr),
        .data_wdata              (data_wdata),
        .data_rdata              (data_rdata),
        .stall                   (stall),
        .grant_instr             (grant_instr),
        .grant_data              (grant_data),
        .arb_state               (arb_state),
        .cycle_count             (cycle_count),
        .stall_count             (stall_count),
        .contention_count        (contention_count),
        .total_fetch_count       (total_fetch_count),
        .total_data_access_count (total_data_access_count)
    );

    // =========================================================================
    // Clock Generator (100 MHz, 50% Duty Cycle)
    // =========================================================================
    always #(CLK_PERIOD / 2) clk = ~clk;

    // =========================================================================
    // Verification Assertion Task
    // =========================================================================
    task check_condition(input condition, input [8*128-1:0] msg);
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
    // Main Test Stimulus
    // =========================================================================
    initial begin
        // GTKWave Waveform Dump
        $dumpfile("sim/von_neumann.vcd");
        $dumpvars(0, tb_von_neumann);

        // Initialize all stimulus signals
        clk              = 0;
        rst              = 1;
        instr_read_en    = 0;
        instr_addr       = 32'd0;
        data_read_en     = 0;
        data_write_en    = 0;
        data_byte_enable = 4'b0000;
        data_addr        = 32'd0;
        data_wdata       = 32'd0;

        $display("==================================================================");
        $display("   Von Neumann Subsystem Verification & Arbiter Stall Testbench   ");
        $display("   Role 4: ALU & Verification Specialist (Arun Kumar Giri)       ");
        $display("==================================================================");

        // Apply Synchronous Reset
        #(CLK_PERIOD * 2);
        @(negedge clk);
        rst = 0;
        #(CLK_PERIOD);

        // =====================================================================
        // TEST 1: Instruction-Only Fetch Transactions (Zero Contention)
        // =====================================================================
        $display("\n[TEST 1] Verifying Conflict-Free Instruction Fetches...");
        test_count = test_count + 1;

        // Fetch Addr 0x00: NOP (0x00000013)
        @(negedge clk);
        instr_read_en = 1;
        instr_addr    = 32'h0000_0000;
        data_read_en  = 0;
        data_write_en = 0;

        #1;
        check_condition(stall === 1'b0, "No stall asserted for instruction-only fetch at 0x00");
        check_condition(grant_instr === 1'b1, "Bus granted to instruction port");
        check_condition(instr_data === 32'h0000_0013, "Fetched 0x00: 0x00000013 (NOP)");

        // Fetch Addr 0x04: ADDI (0x00500113)
        @(negedge clk);
        instr_addr = 32'h0000_0004;
        #1;
        check_condition(stall === 1'b0, "No stall asserted for instruction-only fetch at 0x04");
        check_condition(instr_data === 32'h0050_0113, "Fetched 0x04: 0x00500113 (ADDI)");

        // Fetch Addr 0x0C: ADD (0x00310233)
        @(negedge clk);
        instr_addr = 32'h0000_000C;
        #1;
        check_condition(stall === 1'b0, "No stall asserted for instruction-only fetch at 0x0C");
        check_condition(instr_data === 32'h0031_0233, "Fetched 0x0C: 0x00310233 (ADD)");

        @(negedge clk);
        instr_read_en = 0;
        #(CLK_PERIOD);

        // =====================================================================
        // TEST 2: Data-Only Transactions (Word & Byte Masking, Zero Contention)
        // =====================================================================
        $display("\n[TEST 2] Verifying Conflict-Free Data Memory Read/Write...");
        test_count = test_count + 1;
        instr_read_en = 0;

        // 2a. Word Write at 0x0000_0040
        @(negedge clk);
        data_addr        = 32'h0000_0040;
        data_wdata       = 32'hDEADBEEF;
        data_byte_enable = 4'b1111;
        data_write_en    = 1;
        data_read_en     = 0;

        #1;
        check_condition(stall === 1'b0, "No stall asserted for data write operation");
        check_condition(grant_data === 1'b1, "Bus granted to data port");

        // Wait for clock edge to commit write, then read back
        @(posedge clk);
        @(negedge clk);
        data_write_en    = 0;
        data_read_en     = 1;
        data_addr        = 32'h0000_0040;

        #1;
        check_condition(stall === 1'b0, "No stall asserted for data read operation");
        check_condition(data_rdata === 32'hDEADBEEF, "Word Write/Read verified: 0xDEADBEEF");

        // 2c. Byte-Enable Masking Write (Byte 1 modified with 0xAA)
        @(negedge clk);
        data_write_en    = 1;
        data_read_en     = 0;
        data_addr        = 32'h0000_0040;
        data_wdata       = 32'h0000_AA00;
        data_byte_enable = 4'b0010;

        @(posedge clk);
        @(negedge clk);
        data_write_en    = 0;
        data_read_en     = 1;
        #1;
        check_condition(data_rdata === 32'hDEADAAEF, "Byte-enable masking verified: 0xDEADAAEF");

        @(negedge clk);
        data_read_en = 0;
        #(CLK_PERIOD);

        // =====================================================================
        // TEST 3: Simultaneous Access Contention & Single-Cycle Stall Validation
        // =====================================================================
        $display("\n[TEST 3] Verifying Bus Contention & Single-Cycle Arbiter Stall (Von Neumann Bottleneck)...");
        test_count = test_count + 1;

        // In the Von Neumann architecture, when instruction fetch and data memory
        // access collide, the arbiter must prioritize data access, assert 'stall',
        // and serve instruction fetch on the subsequent cycle.
        @(negedge clk);
        instr_read_en    = 1;
        instr_addr       = 32'h0000_0010; // Fetch 'SW' instruction (0x00412023)
        data_write_en    = 1;
        data_read_en     = 0;
        data_addr        = 32'h0000_0080;
        data_wdata       = 32'h12345678;
        data_byte_enable = 4'b1111;
        expected_stalls  = expected_stalls + 1;

        // Sub-cycle 3.1: Collision occurs!
        #1;
        check_condition(stall === 1'b1, "Stall correctly asserted due to simultaneous I/D collision");
        check_condition(grant_data === 1'b1, "Arbiter prioritized data write during collision");
        check_condition(grant_instr === 1'b0, "Instruction fetch deferred (grant_instr = 0)");

        // Wait for clock edge to commit write, then data master yields
        @(posedge clk);
        @(negedge clk);
        data_write_en = 0; // Data transaction complete
        // Keep instr_read_en asserted as processor core was stalled
        #1;
        check_condition(stall === 1'b0, "Stall de-asserted on next cycle (1 stall cycle resolved)");
        check_condition(grant_instr === 1'b1, "Bus granted to pending instruction fetch");
        check_condition(instr_data === 32'h0041_2023, "Instruction fetch 0x10 (SW) completed cleanly");

        // Repeat for simultaneous Fetch + Data READ
        @(negedge clk);
        instr_addr      = 32'h0000_0014; // Fetch 'LW' instruction (0x00012283)
        data_read_en    = 1;
        data_addr       = 32'h0000_0080;
        expected_stalls = expected_stalls + 1;

        #1;
        check_condition(stall === 1'b1, "Stall correctly asserted during concurrent Fetch + Data READ");
        check_condition(grant_data === 1'b1, "Arbiter prioritized data read");
        check_condition(data_rdata === 32'h12345678, "Data read returned correct value: 0x12345678");

        @(posedge clk);
        @(negedge clk);
        data_read_en = 0;
        #1;
        check_condition(stall === 1'b0, "Stall de-asserted for deferred fetch");
        check_condition(grant_instr === 1'b1, "Instruction fetch granted after data read");
        check_condition(instr_data === 32'h0001_2283, "Instruction fetch 0x14 (LW) completed cleanly");

        @(negedge clk);
        instr_read_en = 0;
        #(CLK_PERIOD);

        // =====================================================================
        // TEST 4: Back-to-Back Contention Stress Sequence
        // =====================================================================
        $display("\n[TEST 4] Verifying Back-to-Back Contention Stress Sequence...");
        test_count = test_count + 1;

        // Sequence of consecutive cycles with competing requests:
        // 1. Fetch + Data Write
        @(negedge clk);
        instr_read_en    = 1;
        instr_addr       = 32'h0000_0018; // Addr 0x18 (ADD: 0x005202B3)
        data_write_en    = 1;
        data_addr        = 32'h0000_0090;
        data_wdata       = 32'hFEEDFACE;
        data_byte_enable = 4'b1111;
        expected_stalls  = expected_stalls + 1;

        #1;
        check_condition(stall === 1'b1, "Stress Step 1: Contention stall asserted");

        // 2. Fetch resolution
        @(posedge clk);
        @(negedge clk);
        data_write_en = 0; // Serve pending fetch
        #1;
        check_condition(stall === 1'b0, "Stress Step 2: Stall cleared for fetch");
        check_condition(instr_data === 32'h0052_02B3, "Stress Step 2: Addr 0x18 fetched correctly");

        // 3. Immediately trigger another contention on next cycle
        @(negedge clk);
        instr_addr      = 32'h0000_001C; // Addr 0x1C (JAL: 0x0000006F)
        data_read_en    = 1;
        data_addr       = 32'h0000_0090;
        expected_stalls = expected_stalls + 1;

        #1;
        check_condition(stall === 1'b1, "Stress Step 3: Second contention stall asserted");

        // 4. Second resolution
        @(posedge clk);
        @(negedge clk);
        data_read_en = 0;
        #1;
        check_condition(stall === 1'b0, "Stress Step 4: Second stall cleared");
        check_condition(instr_data === 32'h0000_006F, "Stress Step 4: Addr 0x1C fetched correctly");

        @(negedge clk);
        instr_read_en = 0;
        #(CLK_PERIOD * 2);

        // =====================================================================
        // TEST 5: Hardware Telemetry and Stall Counter Accuracy
        // =====================================================================
        $display("\n[TEST 5] Validating Hardware Telemetry & Performance Counters...");
        test_count = test_count + 1;

        check_condition(stall_count == expected_stalls, "stall_count matches expected arbitration stalls");
        check_condition(contention_count == expected_stalls, "contention_count matches injected conflict events");
        check_condition(total_fetch_count > 0, "total_fetch_count successfully accumulated");
        check_condition(total_data_access_count > 0, "total_data_access_count successfully accumulated");

        // =====================================================================
        // FINAL VERIFICATION REPORT
        // =====================================================================
        $display("\n==================================================================");
        $display("            VON NEUMANN SUBSYSTEM TELEMETRY REPORT                ");
        $display("==================================================================");
        $display("  Total Clock Cycles Elapsed : %0d", cycle_count);
        $display("  Total Instruction Fetches  : %0d", total_fetch_count);
        $display("  Total Data Accesses (R/W)  : %0d", total_data_access_count);
        $display("  Contention Events Detected : %0d", contention_count);
        $display("  Total Stall Cycles Incurred: %0d (Structural Penalty)", stall_count);
        $display("==================================================================");

        if (error_count == 0) begin
            $display(" >>> ALL %0d TESTS PASSED SUCCESSFULLY! (0 errors) <<<", test_count);
            $display(" Arbiter Transitions & Von Neumann Stall Penalty Verified.");
        end else begin
            $display(" >>> FAILED: %0d ERRORS DETECTED <<<", error_count);
        end
        $display("==================================================================\n");

        $finish;
    end

endmodule
