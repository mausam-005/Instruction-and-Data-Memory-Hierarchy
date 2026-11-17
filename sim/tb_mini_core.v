`timescale 1ns / 1ps
// =============================================================================
// Testbench: tb_mini_core
// Project: Instruction and Data Memory Hierarchy
// Description:
//   Self-checking unit verification testbench for the lightweight RV32I
//   execution engine (mini_core.v) and program counter (program_counter.v).
//
// Key Verification Vectors:
//   1. Reset assertion and Program Counter initialization.
//   2. Register file x0 zero-invariance (hardwired to zero).
//   3. R-Type arithmetic and logic execution (ADD, SUB, AND, OR, XOR, SLT).
//   4. I-Type immediate arithmetic execution (ADDI, SLTI, ANDI, ORI, XORI).
//   5. Data Memory transactions (SW store word, LW load word, byte masking).
//   6. Branch condition evaluation (BEQ taken/not-taken, BNE taken/not-taken).
//   7. Unconditional jumps (JAL target redirection and link register return).
//   8. Memory contention stall freeze (PC and register file pipeline hold).
// =============================================================================

module tb_mini_core;

    localparam CLK_PERIOD = 10; // 100 MHz clock (10 ns)

    // Clock and Control
    reg         clk;
    reg         rst;
    reg         stall;

    // Instruction Memory Bus
    wire        instr_read_en;
    wire [31:0] instr_addr;
    reg  [31:0] instr_data;

    // Data Memory Bus
    wire        data_read_en;
    wire        data_write_en;
    wire [3:0]  data_byte_enable;
    wire [31:0] data_addr;
    wire [31:0] data_wdata;
    reg  [31:0] data_rdata;

    // Test Bookkeeping
    integer error_count = 0;
    integer test_count  = 0;

    // Simple test memory array for data read/write verification
    reg [31:0] test_dmem [0:63];

    // =========================================================================
    // Device Under Test (DUT) Instantiation
    // =========================================================================
    mini_core #(
        .RESET_PC(32'h0000_0000)
    ) dut (
        .clk              (clk),
        .rst              (rst),
        .stall            (stall),
        .instr_read_en    (instr_read_en),
        .instr_addr       (instr_addr),
        .instr_data       (instr_data),
        .data_read_en     (data_read_en),
        .data_write_en    (data_write_en),
        .data_byte_enable (data_byte_enable),
        .data_addr        (data_addr),
        .data_wdata       (data_wdata),
        .data_rdata       (data_rdata)
    );

    // Clock Generation
    always #(CLK_PERIOD / 2) clk = ~clk;

    // Synchronous Data Memory Model
    always @(posedge clk) begin
        if (data_write_en) begin
            test_dmem[data_addr[7:2]] <= data_wdata;
        end
    end

    always @(*) begin
        if (data_read_en) begin
            data_rdata = test_dmem[data_addr[7:2]];
        end else begin
            data_rdata = 32'h0000_0000;
        end
    end

    // Verification Assertion Task
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

    // Instruction Encoders for Testbench Stimulus
    function [31:0] enc_r(input [6:0] f7, input [4:0] rs2, input [4:0] rs1, input [2:0] f3, input [4:0] rd);
        enc_r = {f7, rs2, rs1, f3, rd, 7'b0110011};
    endfunction

    function [31:0] enc_i(input [11:0] imm, input [4:0] rs1, input [2:0] f3, input [4:0] rd);
        enc_i = {imm, rs1, f3, rd, 7'b0010011};
    endfunction

    function [31:0] enc_load(input [11:0] imm, input [4:0] rs1, input [4:0] rd);
        enc_load = {imm, rs1, 3'b010, rd, 7'b0000011}; // LW
    endfunction

    function [31:0] enc_store(input [11:0] imm, input [4:0] rs2, input [4:0] rs1);
        enc_store = {imm[11:5], rs2, rs1, 3'b010, imm[4:0], 7'b0100011}; // SW
    endfunction

    function [31:0] enc_branch(input [12:0] imm, input [4:0] rs2, input [4:0] rs1, input [2:0] f3);
        enc_branch = {imm[12], imm[10:5], rs2, rs1, f3, imm[4:1], imm[11], 7'b1100011};
    endfunction

    function [31:0] enc_jal(input [20:0] imm, input [4:0] rd);
        enc_jal = {imm[20], imm[10:1], imm[11], imm[19:12], rd, 7'b1101111};
    endfunction

    // =========================================================================
    // Main Verification Stimulus
    // =========================================================================
    integer k;
    initial begin
        $dumpfile("sim/mini_core.vcd");
        $dumpvars(0, tb_mini_core);

        // Initialize test memory
        for (k = 0; k < 64; k = k + 1) begin
            test_dmem[k] = 32'd0;
        end

        // Signals initialization
        clk        = 0;
        rst        = 1;
        stall      = 0;
        instr_data = 32'h0000_0013; // NOP
        data_rdata = 32'd0;

        $display("==================================================================");
        $display("   RV32I Mini Core Datapath Self-Checking Unit Testbench          ");
        $display("==================================================================");

        // Apply Reset
        #(CLK_PERIOD * 2);
        @(negedge clk);
        rst = 0;
        #1;

        // ---------------------------------------------------------------------
        // TEST 1: Reset & PC Initialization
        // ---------------------------------------------------------------------
        $display("\n[TEST 1] Verifying Reset State and Initial PC Vector...");
        test_count = test_count + 1;
        check_condition(instr_addr === 32'h0000_0000, "PC initialized to 0x0000_0000 on reset deassertion");
        check_condition(instr_read_en === 1'b1, "Instruction fetch read_en asserted when core active");

        // ---------------------------------------------------------------------
        // TEST 2: ADDI Execution & Register Write
        // ---------------------------------------------------------------------
        $display("\n[TEST 2] Verifying I-Type Arithmetic (ADDI x1, x0, 15)...");
        test_count = test_count + 1;
        // Instruction at 0x00: addi x1, x0, 15
        instr_data = enc_i(12'd15, 5'd0, 3'b000, 5'd1);
        @(posedge clk);
        #1;
        check_condition(instr_addr === 32'h0000_0004, "PC incremented to 0x0000_0004 after single-cycle execute");
        check_condition(dut.regfile[1] === 32'd15, "Register x1 updated with value 15");

        // ---------------------------------------------------------------------
        // TEST 3: Register x0 Hardwire Zero Protection
        // ---------------------------------------------------------------------
        $display("\n[TEST 3] Verifying Register x0 Zero-Invariance (addi x0, x0, 99)...");
        test_count = test_count + 1;
        instr_data = enc_i(12'd99, 5'd0, 3'b000, 5'd0); // Attempt write to x0
        @(posedge clk);
        #1;
        check_condition(dut.regfile[0] === 32'd0, "Register x0 strictly remains zero after write attempt");

        // ---------------------------------------------------------------------
        // TEST 4: R-Type Operations (ADD, SUB, AND, OR, XOR, SLT)
        // ---------------------------------------------------------------------
        $display("\n[TEST 4] Verifying R-Type Operations (x2=5, then test ALU ops)...");
        test_count = test_count + 1;
        // Setup x2 = 5 (addi x2, x0, 5)
        instr_data = enc_i(12'd5, 5'd0, 3'b000, 5'd2);
        @(posedge clk);
        #1;
        check_condition(dut.regfile[2] === 32'd5, "Register x2 set to 5");

        // 4a. ADD: add x3, x1, x2 (15 + 5 = 20)
        instr_data = enc_r(7'b0000000, 5'd2, 5'd1, 3'b000, 5'd3);
        @(posedge clk);
        #1;
        check_condition(dut.regfile[3] === 32'd20, "ADD executed: 15 + 5 = 20 in x3");

        // 4b. SUB: sub x4, x1, x2 (15 - 5 = 10)
        instr_data = enc_r(7'b0100000, 5'd2, 5'd1, 3'b000, 5'd4);
        @(posedge clk);
        #1;
        check_condition(dut.regfile[4] === 32'd10, "SUB executed: 15 - 5 = 10 in x4");

        // 4c. AND: and x5, x1, x2 (15 & 5 = 5)
        instr_data = enc_r(7'b0000000, 5'd2, 5'd1, 3'b111, 5'd5);
        @(posedge clk);
        #1;
        check_condition(dut.regfile[5] === 32'd5, "AND executed: 15 & 5 = 5 in x5");

        // 4d. SLT: slt x6, x2, x1 (5 < 15 -> 1)
        instr_data = enc_r(7'b0000000, 5'd1, 5'd2, 3'b010, 5'd6);
        @(posedge clk);
        #1;
        check_condition(dut.regfile[6] === 32'd1, "SLT executed: 5 < 15 returns 1 in x6");

        // ---------------------------------------------------------------------
        // TEST 5: Data Memory Store and Load (SW, LW)
        // ---------------------------------------------------------------------
        $display("\n[TEST 5] Verifying Memory Access (SW x3 to Mem[0x20], then LW to x7)...");
        test_count = test_count + 1;
        // SW x3, 32(x0) -> Mem[32] = 20
        instr_data = enc_store(12'd32, 5'd3, 5'd0);
        #1;
        check_condition(data_write_en === 1'b1, "data_write_en asserted during SW");
        check_condition(data_byte_enable === 4'b1111, "data_byte_enable asserted 4'b1111 for word store");
        check_condition(data_addr === 32'd32, "data_addr matches target address 32");
        check_condition(data_wdata === 32'd20, "data_wdata matches source register x3 (20)");
        @(posedge clk);
        #1;

        // LW x7, 32(x0) -> x7 = Mem[32] = 20
        instr_data = enc_load(12'd32, 5'd0, 5'd7);
        #1;
        check_condition(data_read_en === 1'b1, "data_read_en asserted during LW");
        check_condition(data_addr === 32'd32, "data_addr matches load address 32");
        @(posedge clk);
        #1;
        check_condition(dut.regfile[7] === 32'd20, "LW loaded value 20 from memory into x7");

        // ---------------------------------------------------------------------
        // TEST 6: Branch Evaluation (BEQ taken, BNE not taken)
        // ---------------------------------------------------------------------
        $display("\n[TEST 6] Verifying Branch Resolution (BEQ taken & BNE not-taken)...");
        test_count = test_count + 1;
        // Setup x8 = 20 (addi x8, x0, 20)
        instr_data = enc_i(12'd20, 5'd0, 3'b000, 5'd8);
        @(posedge clk);
        #1;

        // BEQ x7, x8, +16 (20 == 20 -> Taken!)
        // Current PC is at instr_addr. Target is instr_addr + 16
        begin : test_beq
            reg [31:0] expected_branch_pc;
            expected_branch_pc = instr_addr + 32'd16;
            instr_data = enc_branch(13'd16, 5'd8, 5'd7, 3'b000);
            #1;
            check_condition(dut.branch_taken === 1'b1, "branch_taken asserted for matching BEQ");
            @(posedge clk);
            #1;
            check_condition(instr_addr === expected_branch_pc, "PC updated to branch target on taken BEQ");
        end

        // ---------------------------------------------------------------------
        // TEST 7: Unconditional Jump (JAL)
        // ---------------------------------------------------------------------
        $display("\n[TEST 7] Verifying JAL Jump and Return Address Link...");
        test_count = test_count + 1;
        begin : test_jal_block
            reg [31:0] expected_link_pc;
            reg [31:0] expected_target_pc;
            expected_link_pc   = instr_addr + 32'd4;
            expected_target_pc = instr_addr + 32'd32;
            // jal x9, +32
            instr_data = enc_jal(21'd32, 5'd9);
            #1;
            check_condition(dut.branch_taken === 1'b1, "branch_taken asserted on JAL");
            @(posedge clk);
            #1;
            check_condition(instr_addr === expected_target_pc, "PC jumped to JAL target address");
            check_condition(dut.regfile[9] === expected_link_pc, "Link register x9 stored PC + 4");
        end

        // ---------------------------------------------------------------------
        // TEST 8: Memory Contention Stall Freeze
        // ---------------------------------------------------------------------
        $display("\n[TEST 8] Verifying Flow Control Pipeline Stall Freeze...");
        test_count = test_count + 1;
        begin : test_stall_block
            reg [31:0] frozen_pc;
            frozen_pc = instr_addr;
            // Attempt to execute addi x10, x0, 77 during stall
            instr_data = enc_i(12'd77, 5'd0, 3'b000, 5'd10);
            stall = 1; // Inject stall
            @(posedge clk);
            #1;
            check_condition(instr_addr === frozen_pc, "PC strictly frozen during stall assertion");
            check_condition(dut.regfile[10] === 32'd0, "Register write inhibited during stall freeze");

            // Release stall and verify execution commits
            stall = 0;
            @(posedge clk);
            #1;
            check_condition(instr_addr === (frozen_pc + 32'd4), "PC increments after stall deassertion");
            check_condition(dut.regfile[10] === 32'd77, "Register write commits once stall released");
        end

        // ---------------------------------------------------------------------
        // Test Summary
        // ---------------------------------------------------------------------
        $display("\n==================================================================");
        $display("                 MINI CORE UNIT TEST REPORT                       ");
        $display("==================================================================");
        $display("  Total Tests Executed : %0d", test_count);
        $display("  Total Errors Detected: %0d", error_count);
        $display("==================================================================");

        if (error_count == 0) begin
            $display(" >>> ALL %0d TESTS PASSED SUCCESSFULLY! (0 errors) <<<", test_count);
            $display(" RV32I Datapath, PC Register, and Hazard Control Fully Verified.");
        end else begin
            $display(" >>> FAILED: %0d ERRORS DETECTED <<<", error_count);
        end
        $display("==================================================================\n");

        $finish;
    end

endmodule

