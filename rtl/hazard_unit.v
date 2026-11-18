`timescale 1ns / 1ps
// =============================================================================
// Project: Instruction and Data Memory Hierarchy (Phase II)
// Module : hazard_unit.v
// Author : Arun Kumar Giri (2401010099) - Role 4: Pipeline Hazards, Forwarding & Verification Specialist
// Description:
//   Synthesizable Pipeline Hazard Detection and Stage Interlock Controller for
//   the 5-Stage RV32I Processor.
//
// Key Responsibilities:
//   1. Load-Use Data Hazard Detection:
//      Identifies when an instruction currently in the ID stage depends on the
//      destination register of a memory Load (LW, LB, LH, LBU, LHU) currently
//      executing in the EX stage. Resolves this RAW dependency by:
//        - Freezing Program Counter (stall_pc = 1)
//        - Freezing IF/ID stage register (stall_if_id = 1)
//        - Injecting a 1-cycle bubble into ID/EX stage register (flush_id_ex = 1)
//      Accurately decodes id_opcode so that immediate-field bits [24:20] of
//      I-type ALU and Load instructions are NOT falsely matched as an rs2 source.
//
//   2. Multi-Cycle Cache Miss Refill Freeze (Harvard & Unified):
//      Synchronously freezes all 5 pipeline stages (PC, IF/ID, ID/EX, EX/MEM,
//      MEM/WB) whenever an L1 I-Cache, L1 D-Cache, or backing memory burst refill
//      or write-through transaction is active (icache_stall, dcache_stall, ext_stall).
//
//   3. Structural Contention (Von Neumann Unified Bus):
//      Accommodates single-port memory contention (stall_fetch) by holding PC
//      while memory-stage Load/Store accesses take priority, preventing stage
//      register corruption.
//
//   4. Control Hazard Squashing (Branch / Jump Taken):
//      Squashes speculative instructions in IF/ID and ID/EX registers on branch
//      condition satisfaction (BEQ, BNE, BLT, BGE, BLTU, BGEU) or jump (JAL, JALR).
// =============================================================================

module hazard_unit (
    // -------------------------------------------------------------------------
    // ID Stage Instruction Fields
    // -------------------------------------------------------------------------
    input  wire [6:0]  id_opcode,
    input  wire [4:0]  id_rs1,
    input  wire [4:0]  id_rs2,

    // -------------------------------------------------------------------------
    // EX Stage Execution & Branch Status
    // -------------------------------------------------------------------------
    input  wire [4:0]  ex_rd,
    input  wire        ex_mem_read,      // 1: EX stage instruction is a Load
    input  wire        ex_branch_taken,  // 1: Branch condition met or unconditional jump

    // -------------------------------------------------------------------------
    // Memory Subsystem & Cache Refill Stall Inputs
    // -------------------------------------------------------------------------
    input  wire        icache_stall,     // L1 I-Cache burst refill in progress
    input  wire        dcache_stall,     // L1 D-Cache burst refill / write-through in progress
    input  wire        ext_stall,        // External global bus stall
    input  wire        stall_fetch,      // Structural fetch contention stall (Von Neumann)

    // -------------------------------------------------------------------------
    // Inter-stage Pipeline Register Controls
    // -------------------------------------------------------------------------
    output wire        stall_pc,
    output wire        stall_if_id,
    output wire        stall_id_ex,
    output wire        stall_ex_mem,
    output wire        stall_mem_wb,
    output wire        flush_if_id,
    output wire        flush_id_ex,
    output wire        flush_ex_mem,
    output wire        flush_mem_wb,

    // -------------------------------------------------------------------------
    // Hazard Status Diagnostics & Telemetry Probes
    // -------------------------------------------------------------------------
    output wire        load_use_hazard,
    output wire        pipeline_stall,   // Unified cache freeze signal
    output wire        pipeline_freeze,  // Synonym for pipeline_stall
    output wire        control_hazard    // Asserted on taken branch/jump flush
);

    // =========================================================================
    // RV32I Opcode Definitions
    // =========================================================================
    localparam [6:0] OPCODE_R_TYPE = 7'b0110011; // ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND
    localparam [6:0] OPCODE_I_TYPE = 7'b0010011; // ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI
    localparam [6:0] OPCODE_LOAD   = 7'b0000011; // LB, LH, LW, LBU, LHU
    localparam [6:0] OPCODE_STORE  = 7'b0100011; // SB, SH, SW
    localparam [6:0] OPCODE_BRANCH = 7'b1100011; // BEQ, BNE, BLT, BGE, BLTU, BGEU
    localparam [6:0] OPCODE_JAL    = 7'b1101111; // JAL
    localparam [6:0] OPCODE_JALR   = 7'b1100111; // JALR
    localparam [6:0] OPCODE_LUI    = 7'b0110111; // LUI
    localparam [6:0] OPCODE_AUIPC  = 7'b0010111; // AUIPC

    // =========================================================================
    // Source Register Usage Decoding
    // =========================================================================
    // Instructions reading rs1: R-Type, I-Type ALU, Load, Store, Branch, JALR
    wire id_uses_rs1 = (id_opcode == OPCODE_R_TYPE) ||
                       (id_opcode == OPCODE_I_TYPE) ||
                       (id_opcode == OPCODE_LOAD)   ||
                       (id_opcode == OPCODE_STORE)  ||
                       (id_opcode == OPCODE_BRANCH) ||
                       (id_opcode == OPCODE_JALR);

    // Instructions reading rs2: R-Type, Store, Branch ONLY.
    // (Crucial: I-Type ALU and Loads use bits [24:20] for immediate, not rs2)
    wire id_uses_rs2 = (id_opcode == OPCODE_R_TYPE) ||
                       (id_opcode == OPCODE_STORE)  ||
                       (id_opcode == OPCODE_BRANCH);

    // =========================================================================
    // 1. Load-Use Data Hazard Detection Logic
    // =========================================================================
    // Occurs when:
    //   - Instruction in EX is a LOAD (ex_mem_read == 1)
    //   - Destination register ex_rd is valid (not x0)
    //   - Instruction in ID actively consumes ex_rd via rs1 or rs2
    assign load_use_hazard = ex_mem_read && (ex_rd != 5'd0) &&
                             ((id_uses_rs1 && (ex_rd == id_rs1)) ||
                              (id_uses_rs2 && (ex_rd == id_rs2)));

    // =========================================================================
    // 2. Global Pipeline Freeze (Cache Line Refills / External Wait)
    // =========================================================================
    assign pipeline_stall  = icache_stall || dcache_stall || ext_stall;
    assign pipeline_freeze = pipeline_stall;
    assign control_hazard  = ex_branch_taken;

    // =========================================================================
    // 3. Stage-by-Stage Stall & Flush Control Generation
    // =========================================================================

    // Program Counter (PC):
    // Freeze when caches miss, load-use hazard requires a bubble, or fetch is contending.
    assign stall_pc     = pipeline_stall || load_use_hazard || stall_fetch;

    // IF/ID Pipeline Register:
    // Hold current instruction when caches miss or load-use hazard stalls decode.
    // Flush when a branch/jump is taken (and not frozen by cache miss).
    assign stall_if_id  = pipeline_stall || load_use_hazard;
    assign flush_if_id  = ex_branch_taken && !pipeline_stall;

    // ID/EX Pipeline Register:
    // Hold state during cache refill.
    // Flush (inject bubble) on load-use hazard stall or branch redirection.
    assign stall_id_ex  = pipeline_stall;
    assign flush_id_ex  = (load_use_hazard || ex_branch_taken) && !pipeline_stall;

    // EX/MEM Pipeline Register:
    // Freeze during multi-cycle cache refill.
    assign stall_ex_mem = pipeline_stall;
    assign flush_ex_mem = 1'b0;

    // MEM/WB Pipeline Register:
    // Freeze during multi-cycle cache refill.
    assign stall_mem_wb = pipeline_stall;
    assign flush_mem_wb = 1'b0;

endmodule
