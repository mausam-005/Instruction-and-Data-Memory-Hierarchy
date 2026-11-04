`timescale 1ns / 1ps
// =============================================================================
// Module: alu
// Project: Instruction and Data Memory Hierarchy
// Role 4: ALU & Verification Specialist (Arun Kumar Giri)
// Description:
//   Synthesizable 32-bit Arithmetic Logic Unit (ALU) supporting core RV32I
//   operations:
//     - ADD  : Addition
//     - SUB  : Subtraction
//     - AND  : Bitwise AND
//     - OR   : Bitwise OR
//     - XOR  : Bitwise Exclusive-OR
//     - SLT  : Set on Less Than (signed comparison)
//     - SLTU : Set on Less Than (unsigned comparison)
//     - SLL  : Shift Left Logical
//     - SRL  : Shift Right Logical
//     - SRA  : Shift Right Arithmetic
//     - PASS : Pass operand B
//   Computes status flags: zero, negative, carry, overflow.
// =============================================================================

module alu #(
    parameter DATA_WIDTH = 32
)(
    input  wire [DATA_WIDTH-1:0] a,            // Operand A (e.g. rs1)
    input  wire [DATA_WIDTH-1:0] b,            // Operand B (e.g. rs2 or immediate)
    input  wire [3:0]            alu_control,  // ALU operation selector
    output reg  [DATA_WIDTH-1:0] result,       // 32-bit computed result
    output wire                  zero,         // Asserted if result == 0 (for BEQ/BNE)
    output wire                  negative,     // Asserted if result is negative (MSB == 1)
    output reg                   carry,        // Unsigned carry-out / borrow
    output reg                   overflow      // Signed arithmetic overflow flag
);

    // =========================================================================
    // ALU Operation Code Definitions
    // =========================================================================
    localparam [3:0] ALU_ADD  = 4'b0000; // 0: ADD (a + b)
    localparam [3:0] ALU_SUB  = 4'b0001; // 1: SUB (a - b)
    localparam [3:0] ALU_AND  = 4'b0010; // 2: AND (a & b)
    localparam [3:0] ALU_OR   = 4'b0011; // 3: OR  (a | b)
    localparam [3:0] ALU_XOR  = 4'b0100; // 4: XOR (a ^ b)
    localparam [3:0] ALU_SLT  = 4'b0101; // 5: SLT (signed a < b)
    localparam [3:0] ALU_SLTU = 4'b0110; // 6: SLTU (unsigned a < b)
    localparam [3:0] ALU_SLL  = 4'b0111; // 7: SLL (a << b[4:0])
    localparam [3:0] ALU_SRL  = 4'b1000; // 8: SRL (a >> b[4:0])
    localparam [3:0] ALU_SRA  = 4'b1001; // 9: SRA (signed(a) >>> b[4:0])
    localparam [3:0] ALU_PASS = 4'b1010; // 10: PASS B

    // Shift amount (lower 5 bits of operand B for 32-bit word)
    wire [4:0] shamt = b[4:0];

    // Intermediate addition/subtraction with carry detection (33-bit)
    wire [DATA_WIDTH:0] add_ext = {1'b0, a} + {1'b0, b};
    wire [DATA_WIDTH:0] sub_ext = {1'b0, a} - {1'b0, b};

    // =========================================================================
    // Combinational Computation Logic
    // =========================================================================
    always @(*) begin
        // Defaults
        result   = {DATA_WIDTH{1'b0}};
        carry    = 1'b0;
        overflow = 1'b0;

        case (alu_control)
            ALU_ADD: begin
                result   = a + b;
                carry    = add_ext[DATA_WIDTH];
                // Overflow occurs if both inputs have the same sign bit and result sign differs
                overflow = (a[DATA_WIDTH-1] == b[DATA_WIDTH-1]) && (result[DATA_WIDTH-1] != a[DATA_WIDTH-1]);
            end

            ALU_SUB: begin
                result   = a - b;
                carry    = sub_ext[DATA_WIDTH]; // Borrow flag for unsigned subtraction
                // Overflow occurs if inputs have opposite signs and result sign differs from operand A
                overflow = (a[DATA_WIDTH-1] != b[DATA_WIDTH-1]) && (result[DATA_WIDTH-1] != a[DATA_WIDTH-1]);
            end

            ALU_AND: begin
                result = a & b;
            end

            ALU_OR: begin
                result = a | b;
            end

            ALU_XOR: begin
                result = a ^ b;
            end

            ALU_SLT: begin
                // Signed comparison: 1 if A < B, else 0
                result = ($signed(a) < $signed(b)) ? {{(DATA_WIDTH-1){1'b0}}, 1'b1} : {DATA_WIDTH{1'b0}};
            end

            ALU_SLTU: begin
                // Unsigned comparison: 1 if A < B, else 0
                result = (a < b) ? {{(DATA_WIDTH-1){1'b0}}, 1'b1} : {DATA_WIDTH{1'b0}};
            end

            ALU_SLL: begin
                result = a << shamt;
            end

            ALU_SRL: begin
                result = a >> shamt;
            end

            ALU_SRA: begin
                result = $signed(a) >>> shamt;
            end

            ALU_PASS: begin
                result = b;
            end

            default: begin
                result   = {DATA_WIDTH{1'b0}};
                carry    = 1'b0;
                overflow = 1'b0;
            end
        endcase
    end

    // =========================================================================
    // Status Flags
    // =========================================================================
    assign zero     = (result == {DATA_WIDTH{1'b0}});
    assign negative = result[DATA_WIDTH-1];

endmodule
