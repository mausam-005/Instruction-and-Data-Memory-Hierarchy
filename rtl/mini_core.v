`timescale 1ns / 1ps
// =============================================================================
// Module: mini_core
// Description:
//   Lightweight single-cycle RV32I execution engine datapath integrating:
//     - 32-bit Program Counter register (program_counter)
//     - 32-bit Arithmetic Logic Unit (alu)
//     - 32 x 32-bit Register File (x0 hardwired to zero)
//     - Instruction Decoder supporting:
//         * R-Type: ADD, SUB, AND, OR, XOR, SLT
//         * I-Type: ADDI, LW
//         * S-Type: SW
//         * B-Type: BEQ, BNE
//         * J-Type: JAL
//     - Memory bus interfaces for instruction fetch and data access.
//     - Pipeline flow control supporting memory contention stalls.
// =============================================================================

module mini_core #(
    parameter RESET_PC = 32'h0000_0000
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        stall,

    // Instruction Fetch Interface
    output wire        instr_read_en,
    output wire [31:0] instr_addr,
    input  wire [31:0] instr_data,

    // Data Memory Interface
    output wire        data_read_en,
    output wire        data_write_en,
    output wire [3:0]  data_byte_enable,
    output wire [31:0] data_addr,
    output wire [31:0] data_wdata,
    input  wire [31:0] data_rdata
);

    // =========================================================================
    // RV32I Opcode Definitions
    // =========================================================================
    localparam [6:0] OPCODE_R_TYPE = 7'b0110011; // ADD, SUB, AND, OR, XOR, SLT
    localparam [6:0] OPCODE_I_TYPE = 7'b0010011; // ADDI
    localparam [6:0] OPCODE_LOAD   = 7'b0000011; // LW
    localparam [6:0] OPCODE_STORE  = 7'b0100011; // SW
    localparam [6:0] OPCODE_BRANCH = 7'b1100011; // BEQ, BNE
    localparam [6:0] OPCODE_JAL    = 7'b1101111; // JAL

    // =========================================================================
    // ALU Control Operation Codes (matching rtl/alu.v)
    // =========================================================================
    localparam [3:0] ALU_ADD  = 4'b0000;
    localparam [3:0] ALU_SUB  = 4'b0001;
    localparam [3:0] ALU_AND  = 4'b0010;
    localparam [3:0] ALU_OR   = 4'b0011;
    localparam [3:0] ALU_XOR  = 4'b0100;
    localparam [3:0] ALU_SLT  = 4'b0101;
    localparam [3:0] ALU_SLTU = 4'b0110;
    localparam [3:0] ALU_SLL  = 4'b0111;
    localparam [3:0] ALU_SRL  = 4'b1000;
    localparam [3:0] ALU_SRA  = 4'b1001;
    localparam [3:0] ALU_PASS = 4'b1010;

    // Write-back source selection
    localparam [1:0] WB_ALU = 2'b00;
    localparam [1:0] WB_MEM = 2'b01;
    localparam [1:0] WB_PC4 = 2'b10;

    // =========================================================================
    // Program Counter Signals and Instantiation
    // =========================================================================
    wire [31:0] pc;
    wire        branch_taken;
    wire [31:0] branch_target;

    program_counter #(
        .RESET_PC(RESET_PC)
    ) u_program_counter (
        .clk           (clk),
        .rst           (rst),
        .stall         (stall),
        .branch_taken  (branch_taken),
        .branch_target (branch_target),
        .pc            (pc)
    );

    // Instruction bus connections
    assign instr_addr    = pc;
    assign instr_read_en = ~rst;

    // =========================================================================
    // Instruction Field Decomposition
    // =========================================================================
    wire [31:0] instr  = instr_data;
    wire [6:0]  opcode = instr[6:0];
    wire [4:0]  rd     = instr[11:7];
    wire [2:0]  funct3 = instr[14:12];
    wire [4:0]  rs1    = instr[19:15];
    wire [4:0]  rs2    = instr[24:20];
    wire [6:0]  funct7 = instr[31:25];

    // =========================================================================
    // Immediate Generation (Sign-extended to 32 bits)
    // =========================================================================
    wire [31:0] imm_i = {{20{instr[31]}}, instr[31:20]};
    wire [31:0] imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
    wire [31:0] imm_b = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
    wire [31:0] imm_j = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};

    // =========================================================================
    // 32 x 32-bit Register File
    // =========================================================================
    reg [31:0] regfile [0:31];
    wire [31:0] rs1_data;
    wire [31:0] rs2_data;
    reg  [31:0] reg_wdata;
    reg         reg_write;

    // Asynchronous dual read (x0 hardwired to zero)
    assign rs1_data = (rs1 == 5'd0) ? 32'd0 : regfile[rs1];
    assign rs2_data = (rs2 == 5'd0) ? 32'd0 : regfile[rs2];

    // Synchronous write gated by stall with protection for x0
    wire reg_write_effective = reg_write && (!stall) && (rd != 5'd0);

    integer idx;
    initial begin
        for (idx = 0; idx < 32; idx = idx + 1) begin
            regfile[idx] = 32'd0;
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (idx = 0; idx < 32; idx = idx + 1) begin
                regfile[idx] <= 32'd0;
            end
        end else if (reg_write_effective) begin
            regfile[rd] <= reg_wdata;
        end
    end

    // =========================================================================
    // Control & ALU Decoding
    // =========================================================================
    reg [3:0] alu_control;
    reg [31:0] alu_b;
    reg [1:0]  wb_sel;

    always @(*) begin
        // Safe default assignments
        alu_b       = rs2_data;
        alu_control = ALU_ADD;
        reg_write   = 1'b0;
        wb_sel      = WB_ALU;

        case (opcode)
            OPCODE_R_TYPE: begin
                alu_b     = rs2_data;
                reg_write = 1'b1;
                wb_sel    = WB_ALU;
                case (funct3)
                    3'b000:  alu_control = (funct7[5]) ? ALU_SUB : ALU_ADD; // SUB / ADD
                    3'b001:  alu_control = ALU_SLL;
                    3'b010:  alu_control = ALU_SLT;
                    3'b011:  alu_control = ALU_SLTU;
                    3'b100:  alu_control = ALU_XOR;
                    3'b101:  alu_control = (funct7[5]) ? ALU_SRA : ALU_SRL;
                    3'b110:  alu_control = ALU_OR;
                    3'b111:  alu_control = ALU_AND;
                    default: alu_control = ALU_ADD;
                endcase
            end

            OPCODE_I_TYPE: begin
                alu_b     = imm_i;
                reg_write = 1'b1;
                wb_sel    = WB_ALU;
                case (funct3)
                    3'b000:  alu_control = ALU_ADD; // ADDI
                    3'b010:  alu_control = ALU_SLT;
                    3'b011:  alu_control = ALU_SLTU;
                    3'b100:  alu_control = ALU_XOR;
                    3'b110:  alu_control = ALU_OR;
                    3'b111:  alu_control = ALU_AND;
                    3'b001:  alu_control = ALU_SLL;
                    3'b101:  alu_control = (funct7[5]) ? ALU_SRA : ALU_SRL;
                    default: alu_control = ALU_ADD;
                endcase
            end

            OPCODE_LOAD: begin
                alu_b       = imm_i;
                alu_control = ALU_ADD; // Effective Address = rs1 + imm_i
                reg_write   = 1'b1;
                wb_sel      = WB_MEM;
            end

            OPCODE_STORE: begin
                alu_b       = imm_s;
                alu_control = ALU_ADD; // Effective Address = rs1 + imm_s
                reg_write   = 1'b0;
                wb_sel      = WB_ALU;
            end

            OPCODE_BRANCH: begin
                alu_b       = rs2_data;
                alu_control = ALU_SUB; // Subtraction for equality comparison
                reg_write   = 1'b0;
                wb_sel      = WB_ALU;
            end

            OPCODE_JAL: begin
                alu_b       = imm_j;
                alu_control = ALU_ADD;
                reg_write   = 1'b1;
                wb_sel      = WB_PC4;
            end

            default: begin
                alu_b       = rs2_data;
                alu_control = ALU_ADD;
                reg_write   = 1'b0;
                wb_sel      = WB_ALU;
            end
        endcase
    end

    // =========================================================================
    // ALU Instantiation
    // =========================================================================
    wire [31:0] alu_a = rs1_data;
    wire [31:0] alu_result;
    wire        alu_zero;
    wire        alu_negative;
    wire        alu_carry;
    wire        alu_overflow;

    alu #(
        .DATA_WIDTH(32)
    ) u_alu (
        .a           (alu_a),
        .b           (alu_b),
        .alu_control (alu_control),
        .result      (alu_result),
        .zero        (alu_zero),
        .negative    (alu_negative),
        .carry       (alu_carry),
        .overflow    (alu_overflow)
    );

    // =========================================================================
    // Branch & Jump Resolution
    // =========================================================================
    reg branch_cond;
    always @(*) begin
        case (funct3)
            3'b000:  branch_cond = alu_zero;       // BEQ
            3'b001:  branch_cond = ~alu_zero;      // BNE
            3'b100:  branch_cond = alu_negative ^ alu_overflow; // BLT
            3'b101:  branch_cond = ~(alu_negative ^ alu_overflow); // BGE
            3'b110:  branch_cond = ~alu_carry;     // BLTU
            3'b111:  branch_cond = alu_carry;      // BGEU
            default: branch_cond = 1'b0;
        endcase
    end

    wire is_branch = (opcode == OPCODE_BRANCH);
    wire is_jal    = (opcode == OPCODE_JAL);

    assign branch_taken  = (!stall) && ((is_branch && branch_cond) || is_jal);
    assign branch_target = (is_jal) ? (pc + imm_j) : (pc + imm_b);

    // =========================================================================
    // Write-Back Multiplexer
    // =========================================================================
    always @(*) begin
        case (wb_sel)
            WB_MEM:  reg_wdata = data_rdata;
            WB_PC4:  reg_wdata = pc + 32'd4;
            default: reg_wdata = alu_result;
        endcase
    end

    // =========================================================================
    // Data Memory Bus Assignments
    // =========================================================================
    assign data_read_en     = (opcode == OPCODE_LOAD);
    assign data_write_en    = (opcode == OPCODE_STORE);
    assign data_byte_enable = (opcode == OPCODE_STORE) ? 4'b1111 : 4'b0000;
    assign data_addr        = alu_result;
    assign data_wdata       = rs2_data;

endmodule

