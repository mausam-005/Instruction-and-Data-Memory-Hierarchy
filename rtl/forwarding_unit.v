`timescale 1ns / 1ps
// =============================================================================
// Project: Instruction and Data Memory Hierarchy (Phase II)
// Module : forwarding_unit.v
// Author : Arun Kumar Giri (2401010099) - Role 4: Pipeline Hazards, Forwarding & Verification Specialist
// Description:
//   Synthesizable ALU Operand Forwarding / Bypass Unit for the 5-Stage RV32I Core.
//
// Key Responsibilities:
//   1. EX/MEM -> EX Forwarding (Distance 1 Hazard, forward_sel = 2'b10):
//      Forwards the freshly calculated ALU result, memory load data, or PC+4
//      link address directly from the EX/MEM stage into the EX stage ALU inputs
//      or store data port. Eliminates data hazard stalls for back-to-back arithmetic.
//
//   2. MEM/WB -> EX Forwarding (Distance 2 Hazard, forward_sel = 2'b01):
//      Forwards committed writeback data (from ALU, Memory Load, or PC+4) from
//      the MEM/WB pipeline register into the EX stage inputs.
//
//   3. Forwarding Priority Resolution:
//      When both EX/MEM and MEM/WB stages target the same destination register,
//      the EX/MEM stage takes priority because it represents the most recent
//      architectural instruction in program order.
//
//   4. Zero-Register Immunity (x0 Protection):
//      In RISC-V RV32I, register x0 is hardwired to zero. Attempts to write to
//      x0 are discarded and MUST NEVER trigger operand forwarding (rd != 5'd0).
// =============================================================================

module forwarding_unit (
    // -------------------------------------------------------------------------
    // Execution Stage (EX) Source Register Addresses & Default Operands
    // -------------------------------------------------------------------------
    input  wire [4:0]  ex_rs1,           // Source register 1 address in EX
    input  wire [4:0]  ex_rs2,           // Source register 2 address in EX
    input  wire [31:0] ex_rs1_data,      // Register file operand 1 from ID/EX
    input  wire [31:0] ex_rs2_data,      // Register file operand 2 from ID/EX

    // -------------------------------------------------------------------------
    // Memory Stage (EX/MEM) Forwarding Source (Distance 1)
    // -------------------------------------------------------------------------
    input  wire        mem_reg_write,    // Register write enable in EX/MEM
    input  wire [4:0]  mem_rd,           // Destination register in EX/MEM
    input  wire [31:0] mem_alu_result,   // Computed ALU result in EX/MEM
    input  wire [31:0] mem_rdata,        // Formatted memory load data in EX/MEM
    input  wire [31:0] mem_pc_plus4,     // PC+4 return address in EX/MEM (JAL/JALR)
    input  wire [1:0]  mem_wb_sel,       // 00: ALU, 01: MEM, 10: PC+4

    // -------------------------------------------------------------------------
    // Writeback Stage (MEM/WB) Forwarding Source (Distance 2)
    // -------------------------------------------------------------------------
    input  wire        wb_reg_write,     // Register write enable in MEM/WB
    input  wire [4:0]  wb_rd,            // Destination register in MEM/WB
    input  wire [31:0] wb_reg_wdata,     // Final writeback data in MEM/WB

    // -------------------------------------------------------------------------
    // Forwarding Control Multiplexer Outputs
    // -------------------------------------------------------------------------
    // 2'b00: No forward (use register file read data from ID/EX)
    // 2'b01: Forward from MEM/WB stage
    // 2'b10: Forward from EX/MEM stage
    output reg  [1:0]  forward_a,
    output reg  [1:0]  forward_b,

    // -------------------------------------------------------------------------
    // Multiplexed Operand Values Routed to ALU / Store Data
    // -------------------------------------------------------------------------
    output reg  [31:0] fwd_val_a,
    output reg  [31:0] fwd_val_b,
    output wire [31:0] fwd_store_data
);

    // =========================================================================
    // Writeback Selection Codes
    // =========================================================================
    localparam [1:0] WB_ALU = 2'b00;
    localparam [1:0] WB_MEM = 2'b01;
    localparam [1:0] WB_PC4 = 2'b10;

    // Resolve EX/MEM stage forward value based on instruction type
    reg [31:0] mem_fwd_data;
    always @(*) begin
        case (mem_wb_sel)
            WB_MEM:  mem_fwd_data = mem_rdata;
            WB_PC4:  mem_fwd_data = mem_pc_plus4;
            default: mem_fwd_data = mem_alu_result;
        endcase
    end

    // =========================================================================
    // 1. Forwarding Control Logic for ALU Operand A
    // =========================================================================
    always @(*) begin
        // Priority 1: EX/MEM stage hazard (Distance 1)
        if (mem_reg_write && (mem_rd != 5'd0) && (mem_rd == ex_rs1)) begin
            forward_a = 2'b10;
        // Priority 2: MEM/WB stage hazard (Distance 2)
        end else if (wb_reg_write && (wb_rd != 5'd0) && (wb_rd == ex_rs1)) begin
            forward_a = 2'b01;
        // Default: No forwarding
        end else begin
            forward_a = 2'b00;
        end
    end

    // =========================================================================
    // 2. Forwarding Control Logic for ALU Operand B / Store Data
    // =========================================================================
    always @(*) begin
        // Priority 1: EX/MEM stage hazard (Distance 1)
        if (mem_reg_write && (mem_rd != 5'd0) && (mem_rd == ex_rs2)) begin
            forward_b = 2'b10;
        // Priority 2: MEM/WB stage hazard (Distance 2)
        end else if (wb_reg_write && (wb_rd != 5'd0) && (wb_rd == ex_rs2)) begin
            forward_b = 2'b01;
        // Default: No forwarding
        end else begin
            forward_b = 2'b00;
        end
    end

    // =========================================================================
    // 3. Forwarded Operand Data Multiplexers
    // =========================================================================
    always @(*) begin
        case (forward_a)
            2'b10:   fwd_val_a = mem_fwd_data;
            2'b01:   fwd_val_a = wb_reg_wdata;
            default: fwd_val_a = ex_rs1_data;
        endcase
    end

    always @(*) begin
        case (forward_b)
            2'b10:   fwd_val_b = mem_fwd_data;
            2'b01:   fwd_val_b = wb_reg_wdata;
            default: fwd_val_b = ex_rs2_data;
        endcase
    end

    // Store data forwarded directly to Memory stage
    assign fwd_store_data = fwd_val_b;

endmodule
