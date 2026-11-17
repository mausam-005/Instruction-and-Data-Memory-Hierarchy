`timescale 1ns / 1ps
// =============================================================================
// Module: pipeline_core
// Description:
//   Complete 5-Stage Pipelined RV32I Processor Datapath and Control Subsystem.
//   Stages:
//     1. IF  (Instruction Fetch)   : PC generation and instruction bus request
//     2. ID  (Instruction Decode)  : Register file read, imm generation, control
//     3. EX  (Execution & Address) : ALU operation, forwarding, branch/jump resolution
//     4. MEM (Memory Access)       : Data cache/memory load and store with byte mask
//     5. WB  (Writeback)           : Register file commit from ALU, Memory, or PC+4
//
//   Integrated Hazard & Flow Management:
//     - ALU Operand Forwarding Unit (EX/MEM and MEM/WB to EX stage operands)
//     - Load-Use Data Hazard Detection (1-cycle bubble injection to EX stage)
//     - Control Hazard Flush (squashes speculative IF and ID stages on branch/jump)
//     - Full Pipeline Stall Freeze on external memory/cache line refill contention
// =============================================================================

module pipeline_core #(
    parameter RESET_PC = 32'h0000_0000
)(
    input  wire        clk,
    input  wire        rst,

    // External Pipeline Stall & Structural Hazard Controls
    input  wire        stall,          // Global pipeline freeze (e.g. cache line refill)
    input  wire        stall_fetch,    // Structural fetch stall (holds PC, injects IF/ID bubble)

    // Instruction Memory / I-Cache Interface (Fetch Stage)
    output wire        imem_read_en,
    output wire [31:0] imem_addr,
    input  wire [31:0] imem_rdata,

    // Data Memory / D-Cache Interface (Memory Stage)
    output wire        dmem_read_en,
    output wire        dmem_write_en,
    output wire [3:0]  dmem_byte_enable,
    output wire [31:0] dmem_addr,
    output wire [31:0] dmem_wdata,
    input  wire [31:0] dmem_rdata,

    // Diagnostic & Performance Telemetry Probes
    output wire [31:0] probe_if_pc,
    output wire [31:0] probe_id_pc,
    output wire [31:0] probe_ex_pc,
    output wire [31:0] probe_mem_pc,
    output wire [31:0] probe_wb_pc,
    output wire [31:0] probe_wb_data,
    output wire [4:0]  probe_wb_rd,
    output wire        probe_wb_reg_write,
    output wire        probe_load_use_hazard,
    output wire        probe_branch_taken,
    output wire        probe_instr_retired
);

    // =========================================================================
    // RV32I Opcode & Control Local Parameters
    // =========================================================================
    localparam [6:0] OPCODE_R_TYPE = 7'b0110011; // ADD, SUB, AND, OR, XOR, SLT, SLTU, SLL, SRL, SRA
    localparam [6:0] OPCODE_I_TYPE = 7'b0010011; // ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI
    localparam [6:0] OPCODE_LOAD   = 7'b0000011; // LB, LH, LW, LBU, LHU
    localparam [6:0] OPCODE_STORE  = 7'b0100011; // SB, SH, SW
    localparam [6:0] OPCODE_BRANCH = 7'b1100011; // BEQ, BNE, BLT, BGE, BLTU, BGEU
    localparam [6:0] OPCODE_JAL    = 7'b1101111; // JAL
    localparam [6:0] OPCODE_JALR   = 7'b1100111; // JALR
    localparam [6:0] OPCODE_LUI    = 7'b0110111; // LUI
    localparam [6:0] OPCODE_AUIPC  = 7'b0010111; // AUIPC

    // ALU Operation Codes (matching rtl/alu.v)
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

    // Writeback Selection Codes
    localparam [1:0] WB_ALU = 2'b00;
    localparam [1:0] WB_MEM = 2'b01;
    localparam [1:0] WB_PC4 = 2'b10;

    // =========================================================================
    // Hazard & Flow Control Wires (declared early for inter-stage feedback)
    // =========================================================================
    wire        stall_hazard;      // Asserted on Load-Use data dependency
    wire        ex_branch_taken;   // Asserted on branch condition true or jump in EX
    wire [31:0] branch_target_ex;  // Calculated branch/jump redirection target

    wire stall_pc     = stall || stall_hazard || stall_fetch;
    wire stall_if_id  = (stall || stall_hazard) && !stall_fetch;
    wire flush_if_id  = ex_branch_taken || stall_fetch;
    wire stall_id_ex  = stall;
    wire flush_id_ex  = stall_hazard || ex_branch_taken;
    wire stall_ex_mem = stall;
    wire flush_ex_mem = 1'b0;
    wire stall_mem_wb = stall;
    wire flush_mem_wb = 1'b0;

    // =========================================================================
    // STAGE 1: INSTRUCTION FETCH (IF)
    // =========================================================================
    reg [31:0] if_pc;
    wire [31:0] if_pc_plus4 = if_pc + 32'd4;
    wire [31:0] if_pc_next  = (ex_branch_taken) ? branch_target_ex : if_pc_plus4;

    initial begin
        if_pc = RESET_PC;
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            if_pc <= RESET_PC;
        end else if (!stall_pc) begin
            if_pc <= if_pc_next;
        end
    end

    assign imem_addr    = if_pc;
    assign imem_read_en = ~rst;

    // IF/ID Pipeline Register Instance
    wire [31:0] id_pc;
    wire [31:0] id_pc_plus4;
    wire [31:0] id_instr;

    pipe_reg_if_id u_pipe_if_id (
        .clk         (clk),
        .rst         (rst),
        .stall       (stall_if_id),
        .flush       (flush_if_id),
        .if_pc       (if_pc),
        .if_pc_plus4 (if_pc_plus4),
        .if_instr    (imem_rdata),
        .id_pc       (id_pc),
        .id_pc_plus4 (id_pc_plus4),
        .id_instr    (id_instr)
    );

    // =========================================================================
    // STAGE 2: INSTRUCTION DECODE & REGISTER FETCH (ID)
    // =========================================================================
    wire [6:0] id_opcode = id_instr[6:0];
    wire [4:0] id_rd     = id_instr[11:7];
    wire [2:0] id_funct3 = id_instr[14:12];
    wire [4:0] id_rs1    = id_instr[19:15];
    wire [4:0] id_rs2    = id_instr[24:20];
    wire [6:0] id_funct7 = id_instr[31:25];

    // 32 x 32-bit Register File
    reg [31:0] regfile [0:31];
    integer r_idx;
    initial begin
        for (r_idx = 0; r_idx < 32; r_idx = r_idx + 1) begin
            regfile[r_idx] = 32'd0;
        end
    end

    // Writeback declarations from Stage 5
    wire        wb_reg_write;
    wire [4:0]  wb_rd;
    wire [31:0] wb_reg_wdata;

    // Synchronous writeback commit (with x0 modification protection)
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (r_idx = 0; r_idx < 32; r_idx = r_idx + 1) begin
                regfile[r_idx] <= 32'd0;
            end
        end else if (wb_reg_write && (wb_rd != 5'd0) && !stall) begin
            regfile[wb_rd] <= wb_reg_wdata;
        end
    end

    // Dual asynchronous read
    wire [31:0] rf_rs1_raw = (id_rs1 == 5'd0) ? 32'd0 : regfile[id_rs1];
    wire [31:0] rf_rs2_raw = (id_rs2 == 5'd0) ? 32'd0 : regfile[id_rs2];

    // Internal Write-through Forwarding (WB stage to ID stage write-read bypass)
    wire [31:0] id_rs1_data = (wb_reg_write && (wb_rd != 5'd0) && (wb_rd == id_rs1)) ? wb_reg_wdata : rf_rs1_raw;
    wire [31:0] id_rs2_data = (wb_reg_write && (wb_rd != 5'd0) && (wb_rd == id_rs2)) ? wb_reg_wdata : rf_rs2_raw;

    // Immediate Generation (Sign-extended)
    wire [31:0] imm_i = {{20{id_instr[31]}}, id_instr[31:20]};
    wire [31:0] imm_s = {{20{id_instr[31]}}, id_instr[31:25], id_instr[11:7]};
    wire [31:0] imm_b = {{19{id_instr[31]}}, id_instr[31], id_instr[7], id_instr[30:25], id_instr[11:8], 1'b0};
    wire [31:0] imm_u = {id_instr[31:12], 12'b0};
    wire [31:0] imm_j = {{11{id_instr[31]}}, id_instr[31], id_instr[19:12], id_instr[20], id_instr[30:21], 1'b0};

    // Immediate Selection based on opcode
    reg [31:0] id_imm;
    always @(*) begin
        case (id_opcode)
            OPCODE_STORE:             id_imm = imm_s;
            OPCODE_BRANCH:            id_imm = imm_b;
            OPCODE_LUI, OPCODE_AUIPC: id_imm = imm_u;
            OPCODE_JAL:               id_imm = imm_j;
            default:                  id_imm = imm_i; // I-Type, Load, JALR
        endcase
    end

    // Control Unit Decoding
    reg [3:0]  id_alu_control;
    reg        id_alu_src_b;
    reg [1:0]  id_alu_src_a;
    reg        id_branch;
    reg        id_jump;
    reg        id_jalr;
    reg        id_mem_read;
    reg        id_mem_write;
    reg        id_reg_write;
    reg [1:0]  id_wb_sel;

    always @(*) begin
        // Safe default assignments
        id_alu_control = ALU_ADD;
        id_alu_src_b   = 1'b0; // 0: rs2, 1: imm
        id_alu_src_a   = 2'b00; // 00: rs1, 01: PC (AUIPC), 10: Zero (LUI)
        id_branch      = 1'b0;
        id_jump        = 1'b0;
        id_jalr        = 1'b0;
        id_mem_read    = 1'b0;
        id_mem_write   = 1'b0;
        id_reg_write   = 1'b0;
        id_wb_sel      = WB_ALU;

        case (id_opcode)
            OPCODE_R_TYPE: begin
                id_reg_write = 1'b1;
                id_wb_sel    = WB_ALU;
                id_alu_src_b = 1'b0;
                case (id_funct3)
                    3'b000:  id_alu_control = (id_funct7[5]) ? ALU_SUB : ALU_ADD;
                    3'b001:  id_alu_control = ALU_SLL;
                    3'b010:  id_alu_control = ALU_SLT;
                    3'b011:  id_alu_control = ALU_SLTU;
                    3'b100:  id_alu_control = ALU_XOR;
                    3'b101:  id_alu_control = (id_funct7[5]) ? ALU_SRA : ALU_SRL;
                    3'b110:  id_alu_control = ALU_OR;
                    3'b111:  id_alu_control = ALU_AND;
                    default: id_alu_control = ALU_ADD;
                endcase
            end

            OPCODE_I_TYPE: begin
                id_reg_write = 1'b1;
                id_wb_sel    = WB_ALU;
                id_alu_src_b = 1'b1;
                case (id_funct3)
                    3'b000:  id_alu_control = ALU_ADD;
                    3'b001:  id_alu_control = ALU_SLL;
                    3'b010:  id_alu_control = ALU_SLT;
                    3'b011:  id_alu_control = ALU_SLTU;
                    3'b100:  id_alu_control = ALU_XOR;
                    3'b101:  id_alu_control = (id_funct7[5]) ? ALU_SRA : ALU_SRL;
                    3'b110:  id_alu_control = ALU_OR;
                    3'b111:  id_alu_control = ALU_AND;
                    default: id_alu_control = ALU_ADD;
                endcase
            end

            OPCODE_LOAD: begin
                id_reg_write = 1'b1;
                id_mem_read  = 1'b1;
                id_wb_sel    = WB_MEM;
                id_alu_src_b = 1'b1;
                id_alu_control = ALU_ADD;
            end

            OPCODE_STORE: begin
                id_mem_write = 1'b1;
                id_alu_src_b = 1'b1;
                id_alu_control = ALU_ADD;
            end

            OPCODE_BRANCH: begin
                id_branch    = 1'b1;
                id_alu_src_b = 1'b0;
                id_alu_control = ALU_SUB;
            end

            OPCODE_JAL: begin
                id_jump      = 1'b1;
                id_reg_write = 1'b1;
                id_wb_sel    = WB_PC4;
            end

            OPCODE_JALR: begin
                id_jalr      = 1'b1;
                id_reg_write = 1'b1;
                id_wb_sel    = WB_PC4;
                id_alu_src_b = 1'b1;
                id_alu_control = ALU_ADD;
            end

            OPCODE_LUI: begin
                id_reg_write = 1'b1;
                id_wb_sel    = WB_ALU;
                id_alu_src_a = 2'b10; // Zero
                id_alu_src_b = 1'b1;  // Imm_u
                id_alu_control = ALU_ADD;
            end

            OPCODE_AUIPC: begin
                id_reg_write = 1'b1;
                id_wb_sel    = WB_ALU;
                id_alu_src_a = 2'b01; // PC
                id_alu_src_b = 1'b1;  // Imm_u
                id_alu_control = ALU_ADD;
            end

            default: begin
                // Safe NOP / Bubble defaults
                id_alu_control = ALU_ADD;
                id_alu_src_b   = 1'b0;
                id_alu_src_a   = 2'b00;
                id_branch      = 1'b0;
                id_jump        = 1'b0;
                id_jalr        = 1'b0;
                id_mem_read    = 1'b0;
                id_mem_write   = 1'b0;
                id_reg_write   = 1'b0;
                id_wb_sel      = WB_ALU;
            end
        endcase
    end

    // Load-Use Data Hazard Detection
    // Occurs when instruction in EX stage is a LOAD and writes to rs1 or rs2 of instruction in ID
    wire ex_mem_read;
    wire [4:0] ex_rd;
    assign stall_hazard = ex_mem_read && (ex_rd != 5'd0) &&
                          ((ex_rd == id_rs1) || (ex_rd == id_rs2));

    // ID/EX Pipeline Register Instance
    wire [31:0] ex_pc;
    wire [31:0] ex_pc_plus4;
    wire [31:0] ex_rs1_data;
    wire [31:0] ex_rs2_data;
    wire [31:0] ex_imm;
    wire [4:0]  ex_rs1;
    wire [4:0]  ex_rs2;
    wire [2:0]  ex_funct3;
    wire [6:0]  ex_funct7;
    wire [3:0]  ex_alu_control;
    wire        ex_alu_src_b;
    wire [1:0]  ex_alu_src_a;
    wire        ex_branch;
    wire        ex_jump;
    wire        ex_jalr;
    wire        ex_mem_write;
    wire        ex_reg_write;
    wire [1:0]  ex_wb_sel;

    pipe_reg_id_ex u_pipe_id_ex (
        .clk            (clk),
        .rst            (rst),
        .stall          (stall_id_ex),
        .flush          (flush_id_ex),
        .id_pc          (id_pc),
        .id_pc_plus4    (id_pc_plus4),
        .id_rs1_data    (id_rs1_data),
        .id_rs2_data    (id_rs2_data),
        .id_imm         (id_imm),
        .id_rs1         (id_rs1),
        .id_rs2         (id_rs2),
        .id_rd          (id_rd),
        .id_funct3      (id_funct3),
        .id_funct7      (id_funct7),
        .id_alu_control (id_alu_control),
        .id_alu_src_b   (id_alu_src_b),
        .id_alu_src_a   (id_alu_src_a),
        .id_branch      (id_branch),
        .id_jump        (id_jump),
        .id_jalr        (id_jalr),
        .id_mem_read    (id_mem_read),
        .id_mem_write   (id_mem_write),
        .id_reg_write   (id_reg_write),
        .id_wb_sel      (id_wb_sel),
        .ex_pc          (ex_pc),
        .ex_pc_plus4    (ex_pc_plus4),
        .ex_rs1_data    (ex_rs1_data),
        .ex_rs2_data    (ex_rs2_data),
        .ex_imm         (ex_imm),
        .ex_rs1         (ex_rs1),
        .ex_rs2         (ex_rs2),
        .ex_rd          (ex_rd),
        .ex_funct3      (ex_funct3),
        .ex_funct7      (ex_funct7),
        .ex_alu_control (ex_alu_control),
        .ex_alu_src_b   (ex_alu_src_b),
        .ex_alu_src_a   (ex_alu_src_a),
        .ex_branch      (ex_branch),
        .ex_jump        (ex_jump),
        .ex_jalr        (ex_jalr),
        .ex_mem_read    (ex_mem_read),
        .ex_mem_write   (ex_mem_write),
        .ex_reg_write   (ex_reg_write),
        .ex_wb_sel      (ex_wb_sel)
    );

    // =========================================================================
    // STAGE 3: EXECUTION & ADDRESS CALCULATION (EX)
    // =========================================================================
    // Declarations from MEM Stage for Forwarding
    wire        mem_reg_write;
    wire [4:0]  mem_rd;
    wire [31:0] mem_alu_result;

    // ALU Operand A Forwarding Unit
    reg [1:0] forward_a;
    always @(*) begin
        if (mem_reg_write && (mem_rd != 5'd0) && (mem_rd == ex_rs1)) begin
            forward_a = 2'b10; // Forward from EX/MEM stage
        end else if (wb_reg_write && (wb_rd != 5'd0) && (wb_rd == ex_rs1)) begin
            forward_a = 2'b01; // Forward from MEM/WB stage
        end else begin
            forward_a = 2'b00; // No forwarding
        end
    end

    // ALU Operand B Forwarding Unit
    reg [1:0] forward_b;
    always @(*) begin
        if (mem_reg_write && (mem_rd != 5'd0) && (mem_rd == ex_rs2)) begin
            forward_b = 2'b10; // Forward from EX/MEM stage
        end else if (wb_reg_write && (wb_rd != 5'd0) && (wb_rd == ex_rs2)) begin
            forward_b = 2'b01; // Forward from MEM/WB stage
        end else begin
            forward_b = 2'b00; // No forwarding
        end
    end

    // Forwarded Value Selection for Operand A and B
    reg [31:0] fwd_val_a;
    always @(*) begin
        case (forward_a)
            2'b10:   fwd_val_a = mem_alu_result;
            2'b01:   fwd_val_a = wb_reg_wdata;
            default: fwd_val_a = ex_rs1_data;
        endcase
    end

    reg [31:0] fwd_val_b;
    always @(*) begin
        case (forward_b)
            2'b10:   fwd_val_b = mem_alu_result;
            2'b01:   fwd_val_b = wb_reg_wdata;
            default: fwd_val_b = ex_rs2_data;
        endcase
    end

    // ALU Final Input Multiplexing
    reg [31:0] alu_in_a;
    always @(*) begin
        case (ex_alu_src_a)
            2'b01:   alu_in_a = ex_pc;   // AUIPC
            2'b10:   alu_in_a = 32'd0;   // LUI
            default: alu_in_a = fwd_val_a; // Default register or forwarded
        endcase
    end

    wire [31:0] alu_in_b = (ex_alu_src_b) ? ex_imm : fwd_val_b;

    // 32-bit ALU Instance
    wire [31:0] alu_result;
    wire        alu_zero;
    wire        alu_negative;
    wire        alu_carry;
    wire        alu_overflow;

    alu #(
        .DATA_WIDTH(32)
    ) u_alu (
        .a           (alu_in_a),
        .b           (alu_in_b),
        .alu_control (ex_alu_control),
        .result      (alu_result),
        .zero        (alu_zero),
        .negative    (alu_negative),
        .carry       (alu_carry),
        .overflow    (alu_overflow)
    );

    // Branch Condition Evaluation
    reg branch_cond_met;
    always @(*) begin
        case (ex_funct3)
            3'b000:  branch_cond_met = alu_zero;                       // BEQ
            3'b001:  branch_cond_met = ~alu_zero;                      // BNE
            3'b100:  branch_cond_met = alu_negative ^ alu_overflow;     // BLT
            3'b101:  branch_cond_met = ~(alu_negative ^ alu_overflow); // BGE
            3'b110:  branch_cond_met = ~alu_carry;                     // BLTU
            3'b111:  branch_cond_met = alu_carry;                      // BGEU
            default: branch_cond_met = 1'b0;
        endcase
    end

    assign ex_branch_taken = (ex_branch && branch_cond_met) || ex_jump || ex_jalr;

    // Branch / Jump Target Address Calculation
    assign branch_target_ex = (ex_jalr) ? ((fwd_val_a + ex_imm) & 32'hFFFFFFFE) : (ex_pc + ex_imm);

    // Store data to be passed to MEM stage (uses forwarded register 2 value)
    wire [31:0] ex_store_data = fwd_val_b;

    // EX/MEM Pipeline Register Instance
    wire [31:0] mem_pc;
    wire [31:0] mem_pc_plus4;
    wire [31:0] mem_rs2_data;
    wire [2:0]  mem_funct3;
    wire        mem_mem_read;
    wire        mem_mem_write;
    wire [1:0]  mem_wb_sel;

    pipe_reg_ex_mem u_pipe_ex_mem (
        .clk            (clk),
        .rst            (rst),
        .stall          (stall_ex_mem),
        .flush          (flush_ex_mem),
        .ex_pc          (ex_pc),
        .ex_pc_plus4    (ex_pc_plus4),
        .ex_alu_result  (alu_result),
        .ex_rs2_data    (ex_store_data),
        .ex_rd          (ex_rd),
        .ex_funct3      (ex_funct3),
        .ex_mem_read    (ex_mem_read),
        .ex_mem_write   (ex_mem_write),
        .ex_reg_write   (ex_reg_write),
        .ex_wb_sel      (ex_wb_sel),
        .mem_pc         (mem_pc),
        .mem_pc_plus4   (mem_pc_plus4),
        .mem_alu_result (mem_alu_result),
        .mem_rs2_data   (mem_rs2_data),
        .mem_rd         (mem_rd),
        .mem_funct3     (mem_funct3),
        .mem_mem_read   (mem_mem_read),
        .mem_mem_write  (mem_mem_write),
        .mem_reg_write  (mem_reg_write),
        .mem_wb_sel     (mem_wb_sel)
    );

    // =========================================================================
    // STAGE 4: MEMORY ACCESS (MEM)
    // =========================================================================
    assign dmem_addr     = mem_alu_result;
    assign dmem_read_en  = mem_mem_read;
    assign dmem_write_en = mem_mem_write;

    // Store Data Alignment & Byte Masking (SB, SH, SW)
    reg [3:0]  dmem_byte_en_comb;
    reg [31:0] dmem_wdata_comb;

    always @(*) begin
        dmem_byte_en_comb = 4'b0000;
        dmem_wdata_comb   = mem_rs2_data;

        if (mem_mem_write) begin
            case (mem_funct3)
                3'b000: begin // SB: Store Byte
                    case (mem_alu_result[1:0])
                        2'b00: begin dmem_byte_en_comb = 4'b0001; dmem_wdata_comb = {24'b0, mem_rs2_data[7:0]}; end
                        2'b01: begin dmem_byte_en_comb = 4'b0010; dmem_wdata_comb = {16'b0, mem_rs2_data[7:0], 8'b0}; end
                        2'b10: begin dmem_byte_en_comb = 4'b0100; dmem_wdata_comb = {8'b0, mem_rs2_data[7:0], 16'b0}; end
                        2'b11: begin dmem_byte_en_comb = 4'b1000; dmem_wdata_comb = {mem_rs2_data[7:0], 24'b0}; end
                    endcase
                end

                3'b001: begin // SH: Store Halfword
                    case (mem_alu_result[1])
                        1'b0: begin dmem_byte_en_comb = 4'b0011; dmem_wdata_comb = {16'b0, mem_rs2_data[15:0]}; end
                        1'b1: begin dmem_byte_en_comb = 4'b1100; dmem_wdata_comb = {mem_rs2_data[15:0], 16'b0}; end
                    endcase
                end

                3'b010: begin // SW: Store Word
                    dmem_byte_en_comb = 4'b1111;
                    dmem_wdata_comb   = mem_rs2_data;
                end

                default: begin
                    dmem_byte_en_comb = 4'b1111;
                    dmem_wdata_comb   = mem_rs2_data;
                end
            endcase
        end
    end

    assign dmem_byte_enable = dmem_byte_en_comb;
    assign dmem_wdata       = dmem_wdata_comb;

    // Load Data Sign-Extension & Formatting (LB, LH, LW, LBU, LHU)
    reg [31:0] mem_formatted_rdata;
    always @(*) begin
        case (mem_funct3)
            3'b000: begin // LB: Load Byte (signed)
                case (mem_alu_result[1:0])
                    2'b00: mem_formatted_rdata = {{24{dmem_rdata[7]}}, dmem_rdata[7:0]};
                    2'b01: mem_formatted_rdata = {{24{dmem_rdata[15]}}, dmem_rdata[15:8]};
                    2'b10: mem_formatted_rdata = {{24{dmem_rdata[23]}}, dmem_rdata[23:16]};
                    2'b11: mem_formatted_rdata = {{24{dmem_rdata[31]}}, dmem_rdata[31:24]};
                endcase
            end

            3'b001: begin // LH: Load Halfword (signed)
                case (mem_alu_result[1])
                    1'b0: mem_formatted_rdata = {{16{dmem_rdata[15]}}, dmem_rdata[15:0]};
                    1'b1: mem_formatted_rdata = {{16{dmem_rdata[31]}}, dmem_rdata[31:16]};
                endcase
            end

            3'b010: begin // LW: Load Word
                mem_formatted_rdata = dmem_rdata;
            end

            3'b100: begin // LBU: Load Byte Unsigned
                case (mem_alu_result[1:0])
                    2'b00: mem_formatted_rdata = {24'b0, dmem_rdata[7:0]};
                    2'b01: mem_formatted_rdata = {24'b0, dmem_rdata[15:8]};
                    2'b10: mem_formatted_rdata = {24'b0, dmem_rdata[23:16]};
                    2'b11: mem_formatted_rdata = {24'b0, dmem_rdata[31:24]};
                endcase
            end

            3'b101: begin // LHU: Load Halfword Unsigned
                case (mem_alu_result[1])
                    1'b0: mem_formatted_rdata = {16'b0, dmem_rdata[15:0]};
                    1'b1: mem_formatted_rdata = {16'b0, dmem_rdata[31:16]};
                endcase
            end

            default: mem_formatted_rdata = dmem_rdata;
        endcase
    end

    // MEM/WB Pipeline Register Instance
    wire [31:0] wb_pc;
    wire [31:0] wb_pc_plus4;
    wire [31:0] wb_alu_result;
    wire [31:0] wb_rdata;
    wire [1:0]  wb_wb_sel;

    pipe_reg_mem_wb u_pipe_mem_wb (
        .clk           (clk),
        .rst           (rst),
        .stall         (stall_mem_wb),
        .flush         (flush_mem_wb),
        .mem_pc        (mem_pc),
        .mem_pc_plus4  (mem_pc_plus4),
        .mem_alu_result(mem_alu_result),
        .mem_rdata     (mem_formatted_rdata),
        .mem_rd        (mem_rd),
        .mem_reg_write (mem_reg_write),
        .mem_wb_sel    (mem_wb_sel),
        .wb_pc         (wb_pc),
        .wb_pc_plus4   (wb_pc_plus4),
        .wb_alu_result (wb_alu_result),
        .wb_rdata      (wb_rdata),
        .wb_rd         (wb_rd),
        .wb_reg_write  (wb_reg_write),
        .wb_wb_sel     (wb_wb_sel)
    );

    // =========================================================================
    // STAGE 5: WRITEBACK (WB)
    // =========================================================================
    reg [31:0] wb_data_comb;
    always @(*) begin
        case (wb_wb_sel)
            WB_MEM:  wb_data_comb = wb_rdata;
            WB_PC4:  wb_data_comb = wb_pc_plus4;
            default: wb_data_comb = wb_alu_result;
        endcase
    end

    assign wb_reg_wdata = wb_data_comb;

    // =========================================================================
    // Diagnostic & Telemetry Probe Assignments
    // =========================================================================
    assign probe_if_pc           = if_pc;
    assign probe_id_pc           = id_pc;
    assign probe_ex_pc           = ex_pc;
    assign probe_mem_pc          = mem_pc;
    assign probe_wb_pc           = wb_pc;
    assign probe_wb_data         = wb_reg_wdata;
    assign probe_wb_rd           = wb_rd;
    assign probe_wb_reg_write    = wb_reg_write;
    assign probe_load_use_hazard = stall_hazard;
    assign probe_branch_taken    = ex_branch_taken;
    assign probe_instr_retired   = (wb_reg_write && (wb_rd != 5'd0)) || dmem_write_en || ex_branch;

endmodule

