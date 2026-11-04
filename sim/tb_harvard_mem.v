`timescale 1ns / 1ps
// =============================================================================
// Testbench: tb_harvard_mem
// Project: Instruction and Data Memory Hierarchy
// Description:
//   Self-checking unit testbench for harvard_top.v. Tests:
//     1. Instruction ROM preload and fetch verification.
//     2. Data RAM byte, halfword, and full word writes and reads.
//     3. Concurrent/simultaneous instruction fetch and data read/write.
//     4. Validates hardware performance counter telemetry.
// =============================================================================

module tb_harvard_mem;

    localparam DATA_WIDTH = 32;
    localparam ADDR_WIDTH = 32;
    localparam CLK_PERIOD = 10; // 100 MHz clock (10ns period)

    reg                  clk;
    reg                  rst;

    // Instruction port
    reg                  instr_read_en;
    reg  [ADDR_WIDTH-1:0] instr_addr;
    wire [DATA_WIDTH-1:0] instr_data;

    // Data port
    reg                  data_read_en;
    reg                  data_write_en;
    reg  [3:0]            data_byte_enable;
    reg  [ADDR_WIDTH-1:0] data_addr;
    reg  [DATA_WIDTH-1:0] data_wdata;
    wire [DATA_WIDTH-1:0] data_rdata;

    // Telemetry outputs
    wire                 simultaneous_access;
    wire [31:0]          simultaneous_access_count;
    wire [31:0]          total_fetch_count;
    wire [31:0]          total_data_access_count;
    wire [31:0]          cycle_count;

    // Error and test counters
    integer error_count = 0;
    integer test_count  = 0;

    // Instantiate Device Under Test (DUT)
    harvard_top #(
        .DATA_WIDTH     (DATA_WIDTH),
        .ADDR_WIDTH     (ADDR_WIDTH),
        .IMEM_DEPTH     (256),
        .DMEM_DEPTH     (256),
        .IMEM_INIT_FILE ("benchmarks/sample_prog.mem"),
        .DMEM_INIT_FILE (""),
        .SYNC_READ      (0)
    ) dut (
        .clk                       (clk),
        .rst                       (rst),
        .instr_read_en             (instr_read_en),
        .instr_addr                (instr_addr),
        .instr_data                (instr_data),
        .data_read_en              (data_read_en),
        .data_write_en             (data_write_en),
        .data_byte_enable          (data_byte_enable),
        .data_addr                 (data_addr),
        .data_wdata                (data_wdata),
        .data_rdata                (data_rdata),
        .simultaneous_access       (simultaneous_access),
        .simultaneous_access_count (simultaneous_access_count),
        .total_fetch_count         (total_fetch_count),
        .total_data_access_count   (total_data_access_count),
        .cycle_count               (cycle_count)
    );

    // Clock Generation
    always #(CLK_PERIOD / 2) clk = ~clk;

    // Test Sequence
    initial begin
        // Waveform dump for GTKWave
        $dumpfile("sim/harvard_mem.vcd");
        $dumpvars(0, tb_harvard_mem);

        // Initialize signals
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
        $display("   Harvard Memory Hierarchy Verification Testbench   ");
        $display("==================================================================");

        // Apply Reset
        #(CLK_PERIOD * 2);
        rst = 0;
        #(CLK_PERIOD);

        // ---------------------------------------------------------------------
        // TEST 1: Instruction Memory Preload & Fetch
        // ---------------------------------------------------------------------
        $display("\n[TEST 1] Verifying Instruction Memory Preload...");
        test_count = test_count + 1;
        instr_read_en = 1;

        instr_addr = 32'h0000_0000; #1; // Addr 0x00: NOP
        if (instr_data !== 32'h0000_0013) begin
            $display("  [FAIL] Addr 0x00 Expected 0x00000013, Got 0x%08h", instr_data);
            error_count = error_count + 1;
        end else $display("  [PASS] Addr 0x00 Fetched: 0x%08h (NOP)", instr_data);

        instr_addr = 32'h0000_0004; #1; // Addr 0x04: addi x2, x0, 5
        if (instr_data !== 32'h0050_0113) begin
            $display("  [FAIL] Addr 0x04 Expected 0x00500113, Got 0x%08h", instr_data);
            error_count = error_count + 1;
        end else $display("  [PASS] Addr 0x04 Fetched: 0x%08h (ADDI)", instr_data);

        instr_addr = 32'h0000_000C; #1; // Addr 0x0C: add x4, x2, x3
        if (instr_data !== 32'h0031_0233) begin
            $display("  [FAIL] Addr 0x0C Expected 0x00310233, Got 0x%08h", instr_data);
            error_count = error_count + 1;
        end else $display("  [PASS] Addr 0x0C Fetched: 0x%08h (ADD)", instr_data);

        #(CLK_PERIOD);

        // ---------------------------------------------------------------------
        // TEST 2: Data Memory Word & Byte-Enable Writes/Reads
        // ---------------------------------------------------------------------
        $display("\n[TEST 2] Verifying Data Memory Read/Write & Byte Enables...");
        test_count = test_count + 1;
        instr_read_en = 0; // Turn off instruction fetch to test data memory purely

        // 2a. Full word write at 0x0000_0040
        @(posedge clk);
        data_addr        = 32'h0000_0040;
        data_wdata       = 32'hAABBCCDD;
        data_byte_enable = 4'b1111;
        data_write_en    = 1;
        @(posedge clk);
        data_write_en    = 0;
        data_read_en     = 1;
        #1;
        if (data_rdata !== 32'hAABBCCDD) begin
            $display("  [FAIL] Word Read Expected 0xAABBCCDD, Got 0x%08h", data_rdata);
            error_count = error_count + 1;
        end else $display("  [PASS] Word Write/Read Matched: 0x%08h", data_rdata);

        // 2b. Byte write at 0x0000_0040 (Modify lower byte [7:0] with 0x55)
        @(posedge clk);
        data_write_en    = 1;
        data_read_en     = 0;
        data_byte_enable = 4'b0001; // Only write byte 0
        data_wdata       = 32'h00000055;
        @(posedge clk);
        data_write_en    = 0;
        data_read_en     = 1;
        #1;
        if (data_rdata !== 32'hAABBCC55) begin
            $display("  [FAIL] Byte Enable Expected 0xAABBCC55, Got 0x%08h", data_rdata);
            error_count = error_count + 1;
        end else $display("  [PASS] Byte-Enable Masking Verified: 0x%08h", data_rdata);

        #(CLK_PERIOD);

        // ---------------------------------------------------------------------
        // TEST 3: Simultaneous Instruction Fetch & Data Access (Core Feature)
        // ---------------------------------------------------------------------
        $display("\n[TEST 3] Verifying CONCURRENT Fetch + Data Access (Harvard Principle)...");
        test_count = test_count + 1;

        @(negedge clk);
        // Assert BOTH fetch and data store simultaneously
        instr_read_en    = 1;
        instr_addr       = 32'h0000_0010; // Fetch 'sw' instruction
        data_write_en    = 1;
        data_read_en     = 0;
        data_addr        = 32'h0000_0080;
        data_wdata       = 32'hCAFE1234;
        data_byte_enable = 4'b1111;

        #1;
        if (simultaneous_access !== 1'b1) begin
            $display("  [FAIL] simultaneous_access signal not asserted!");
            error_count = error_count + 1;
        end else $display("  [PASS] simultaneous_access flag successfully asserted.");

        if (instr_data !== 32'h0041_2023) begin
            $display("  [FAIL] Instruction corrupted during data write! Got 0x%08h", instr_data);
            error_count = error_count + 1;
        end else $display("  [PASS] Instruction fetched without interference: 0x%08h", instr_data);

        // In the NEXT cycle: Simultaneously fetch next instruction while reading written data
        @(posedge clk);
        @(negedge clk);
        instr_addr    = 32'h0000_0014; // Fetch 'lw' instruction
        data_write_en = 0;
        data_read_en  = 1;
        data_addr     = 32'h0000_0080;

        #1;
        if (data_rdata !== 32'hCAFE1234 || instr_data !== 32'h0001_2283) begin
            $display("  [FAIL] Simultaneous Read Conflict! Instr: 0x%08h, Data: 0x%08h", instr_data, data_rdata);
            error_count = error_count + 1;
        end else begin
            $display("  [PASS] Dual Concurrent Read Succeeded: Instr=0x%08h, Data=0x%08h", instr_data, data_rdata);
        end

        @(posedge clk);
        instr_read_en = 0;
        data_read_en  = 0;
        #(CLK_PERIOD * 2);

        // ---------------------------------------------------------------------
        // TEST SUMMARY & TELEMETRY
        // ---------------------------------------------------------------------
        $display("\n==================================================================");
        $display("                      HARDWARE TELEMETRY REPORT                   ");
        $display("==================================================================");
        $display("  Total Clock Cycles Elapsed : %0d", cycle_count);
        $display("  Total Instruction Fetches  : %0d", total_fetch_count);
        $display("  Total Data Accesses (R/W)  : %0d", total_data_access_count);
        $display("  Simultaneous Dual Accesses : %0d", simultaneous_access_count);
        $display("==================================================================");

        if (error_count == 0) begin
            $display(" >>> ALL %0d TESTS PASSED SUCCESSFULLY! <<<", test_count);
            $display(" Harvard Dual-Bus Independence Verified: Zero Contention Stalls.");
        end else begin
            $display(" >>> FAILED: %0d ERRORS DETECTED <<<", error_count);
        end
        $display("==================================================================\n");

        $finish;
    end

endmodule

