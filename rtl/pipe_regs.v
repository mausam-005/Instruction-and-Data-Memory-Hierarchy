`timescale 1ns / 1ps
// =============================================================================
// Module: pipe_regs
// Description:
//   Synchronous inter-stage Pipeline Registers for the 5-Stage RV32I Processor:
//     1. pipe_reg_if_id  : Fetch to Decode stage register
//     2. pipe_reg_id_ex  : Decode to Execute stage register
//     3. pipe_reg_ex_mem : Execute to Memory stage register
//     4. pipe_reg_mem_wb : Memory to Writeback stage register
//   Each stage register is equipped with:
//     - Active-high synchronous stall-freeze (stall holds current output)
//     - Active-high synchronous bubble-flush (flush inserts bubble / clears control)
//     - Active-high asynchronous reset (rst)
// =============================================================================

// =============================================================================
// 1. IF/ID Pipeline Register
// =============================================================================
module pipe_reg_if_id (
    input  wire        clk,
    input  wire        rst,
    input  wire        stall,
    input  wire        flush,

    // Inputs from IF Stage
    input  wire [31:0] if_pc,
    input  wire [31:0] if_pc_plus4,
    input  wire [31:0] if_instr,

    // Outputs to ID Stage
    output reg  [31:0] id_pc,
    output reg  [31:0] id_pc_plus4,
    output reg  [31:0] id_instr
);

    initial begin
        id_pc       = 32'd0;
        id_pc_plus4 = 32'd0;
        id_instr    = 32'h00000013; // NOP (addi x0, x0, 0)
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            id_pc       <= 32'd0;
            id_pc_plus4 <= 32'd0;
            id_instr    <= 32'h00000013; // NOP
        end else if (flush) begin
            id_pc       <= 32'd0;
            id_pc_plus4 <= 32'd0;
            id_instr    <= 32'h00000013; // NOP bubble
        end else if (!stall) begin
            id_pc       <= if_pc;
            id_pc_plus4 <= if_pc_plus4;
            id_instr    <= if_instr;
        end
    end

endmodule


// =============================================================================
// 2. ID/EX Pipeline Register
// =============================================================================
module pipe_reg_id_ex (
    input  wire        clk,
    input  wire        rst,
    input  wire        stall,
    input  wire        flush,

    // Datapath Inputs from ID Stage
    input  wire [31:0] id_pc,
    input  wire [31:0] id_pc_plus4,
    input  wire [31:0] id_rs1_data,
    input  wire [31:0] id_rs2_data,
    input  wire [31:0] id_imm,
    input  wire [4:0]  id_rs1,
    input  wire [4:0]  id_rs2,
    input  wire [4:0]  id_rd,
    input  wire [2:0]  id_funct3,
    input  wire [6:0]  id_funct7,

    // Control Inputs from ID Stage
    input  wire [3:0]  id_alu_control,
    input  wire        id_alu_src_b,
    input  wire [1:0]  id_alu_src_a,
    input  wire        id_branch,
    input  wire        id_jump,
    input  wire        id_jalr,
    input  wire        id_mem_read,
    input  wire        id_mem_write,
    input  wire        id_reg_write,
    input  wire [1:0]  id_wb_sel,

    // Datapath Outputs to EX Stage
    output reg  [31:0] ex_pc,
    output reg  [31:0] ex_pc_plus4,
    output reg  [31:0] ex_rs1_data,
    output reg  [31:0] ex_rs2_data,
    output reg  [31:0] ex_imm,
    output reg  [4:0]  ex_rs1,
    output reg  [4:0]  ex_rs2,
    output reg  [4:0]  ex_rd,
    output reg  [2:0]  ex_funct3,
    output reg  [6:0]  ex_funct7,

    // Control Outputs to EX Stage
    output reg  [3:0]  ex_alu_control,
    output reg         ex_alu_src_b,
    output reg  [1:0]  ex_alu_src_a,
    output reg         ex_branch,
    output reg         ex_jump,
    output reg         ex_jalr,
    output reg         ex_mem_read,
    output reg         ex_mem_write,
    output reg         ex_reg_write,
    output reg  [1:0]  ex_wb_sel
);

    initial begin
        ex_pc          = 32'd0;
        ex_pc_plus4    = 32'd0;
        ex_rs1_data    = 32'd0;
        ex_rs2_data    = 32'd0;
        ex_imm         = 32'd0;
        ex_rs1         = 5'd0;
        ex_rs2         = 5'd0;
        ex_rd          = 5'd0;
        ex_funct3      = 3'd0;
        ex_funct7      = 7'd0;
        ex_alu_control = 4'd0;
        ex_alu_src_b   = 1'b0;
        ex_alu_src_a   = 2'b00;
        ex_branch      = 1'b0;
        ex_jump        = 1'b0;
        ex_jalr        = 1'b0;
        ex_mem_read    = 1'b0;
        ex_mem_write   = 1'b0;
        ex_reg_write   = 1'b0;
        ex_wb_sel      = 2'b00;
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            ex_pc          <= 32'd0;
            ex_pc_plus4    <= 32'd0;
            ex_rs1_data    <= 32'd0;
            ex_rs2_data    <= 32'd0;
            ex_imm         <= 32'd0;
            ex_rs1         <= 5'd0;
            ex_rs2         <= 5'd0;
            ex_rd          <= 5'd0;
            ex_funct3      <= 3'd0;
            ex_funct7      <= 7'd0;
            ex_alu_control <= 4'd0;
            ex_alu_src_b   <= 1'b0;
            ex_alu_src_a   <= 2'b00;
            ex_branch      <= 1'b0;
            ex_jump        <= 1'b0;
            ex_jalr        <= 1'b0;
            ex_mem_read    <= 1'b0;
            ex_mem_write   <= 1'b0;
            ex_reg_write   <= 1'b0;
            ex_wb_sel      <= 2'b00;
        end else if (flush) begin
            // Bubble injection: deassert all execution and memory controls
            ex_pc          <= 32'd0;
            ex_pc_plus4    <= 32'd0;
            ex_rs1_data    <= 32'd0;
            ex_rs2_data    <= 32'd0;
            ex_imm         <= 32'd0;
            ex_rs1         <= 5'd0;
            ex_rs2         <= 5'd0;
            ex_rd          <= 5'd0;
            ex_funct3      <= 3'd0;
            ex_funct7      <= 7'd0;
            ex_alu_control <= 4'd0;
            ex_alu_src_b   <= 1'b0;
            ex_alu_src_a   <= 2'b00;
            ex_branch      <= 1'b0;
            ex_jump        <= 1'b0;
            ex_jalr        <= 1'b0;
            ex_mem_read    <= 1'b0;
            ex_mem_write   <= 1'b0;
            ex_reg_write   <= 1'b0;
            ex_wb_sel      <= 2'b00;
        end else if (!stall) begin
            ex_pc          <= id_pc;
            ex_pc_plus4    <= id_pc_plus4;
            ex_rs1_data    <= id_rs1_data;
            ex_rs2_data    <= id_rs2_data;
            ex_imm         <= id_imm;
            ex_rs1         <= id_rs1;
            ex_rs2         <= id_rs2;
            ex_rd          <= id_rd;
            ex_funct3      <= id_funct3;
            ex_funct7      <= id_funct7;
            ex_alu_control <= id_alu_control;
            ex_alu_src_b   <= id_alu_src_b;
            ex_alu_src_a   <= id_alu_src_a;
            ex_branch      <= id_branch;
            ex_jump        <= id_jump;
            ex_jalr        <= id_jalr;
            ex_mem_read    <= id_mem_read;
            ex_mem_write   <= id_mem_write;
            ex_reg_write   <= id_reg_write;
            ex_wb_sel      <= id_wb_sel;
        end
    end

endmodule


// =============================================================================
// 3. EX/MEM Pipeline Register
// =============================================================================
module pipe_reg_ex_mem (
    input  wire        clk,
    input  wire        rst,
    input  wire        stall,
    input  wire        flush,

    // Datapath Inputs from EX Stage
    input  wire [31:0] ex_pc,
    input  wire [31:0] ex_pc_plus4,
    input  wire [31:0] ex_alu_result,
    input  wire [31:0] ex_rs2_data,
    input  wire [4:0]  ex_rd,
    input  wire [2:0]  ex_funct3,

    // Control Inputs from EX Stage
    input  wire        ex_mem_read,
    input  wire        ex_mem_write,
    input  wire        ex_reg_write,
    input  wire [1:0]  ex_wb_sel,

    // Datapath Outputs to MEM Stage
    output reg  [31:0] mem_pc,
    output reg  [31:0] mem_pc_plus4,
    output reg  [31:0] mem_alu_result,
    output reg  [31:0] mem_rs2_data,
    output reg  [4:0]  mem_rd,
    output reg  [2:0]  mem_funct3,

    // Control Outputs to MEM Stage
    output reg         mem_mem_read,
    output reg         mem_mem_write,
    output reg         mem_reg_write,
    output reg  [1:0]  mem_wb_sel
);

    initial begin
        mem_pc         = 32'd0;
        mem_pc_plus4   = 32'd0;
        mem_alu_result = 32'd0;
        mem_rs2_data   = 32'd0;
        mem_rd         = 5'd0;
        mem_funct3     = 3'd0;
        mem_mem_read   = 1'b0;
        mem_mem_write  = 1'b0;
        mem_reg_write  = 1'b0;
        mem_wb_sel     = 2'b00;
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            mem_pc         <= 32'd0;
            mem_pc_plus4   <= 32'd0;
            mem_alu_result <= 32'd0;
            mem_rs2_data   <= 32'd0;
            mem_rd         <= 5'd0;
            mem_funct3     <= 3'd0;
            mem_mem_read   <= 1'b0;
            mem_mem_write  <= 1'b0;
            mem_reg_write  <= 1'b0;
            mem_wb_sel     <= 2'b00;
        end else if (flush) begin
            mem_pc         <= 32'd0;
            mem_pc_plus4   <= 32'd0;
            mem_alu_result <= 32'd0;
            mem_rs2_data   <= 32'd0;
            mem_rd         <= 5'd0;
            mem_funct3     <= 3'd0;
            mem_mem_read   <= 1'b0;
            mem_mem_write  <= 1'b0;
            mem_reg_write  <= 1'b0;
            mem_wb_sel     <= 2'b00;
        end else if (!stall) begin
            mem_pc         <= ex_pc;
            mem_pc_plus4   <= ex_pc_plus4;
            mem_alu_result <= ex_alu_result;
            mem_rs2_data   <= ex_rs2_data;
            mem_rd         <= ex_rd;
            mem_funct3     <= ex_funct3;
            mem_mem_read   <= ex_mem_read;
            mem_mem_write  <= ex_mem_write;
            mem_reg_write  <= ex_reg_write;
            mem_wb_sel     <= ex_wb_sel;
        end
    end

endmodule


// =============================================================================
// 4. MEM/WB Pipeline Register
// =============================================================================
module pipe_reg_mem_wb (
    input  wire        clk,
    input  wire        rst,
    input  wire        stall,
    input  wire        flush,

    // Datapath Inputs from MEM Stage
    input  wire [31:0] mem_pc,
    input  wire [31:0] mem_pc_plus4,
    input  wire [31:0] mem_alu_result,
    input  wire [31:0] mem_rdata,
    input  wire [4:0]  mem_rd,

    // Control Inputs from MEM Stage
    input  wire        mem_reg_write,
    input  wire [1:0]  mem_wb_sel,

    // Datapath Outputs to WB Stage
    output reg  [31:0] wb_pc,
    output reg  [31:0] wb_pc_plus4,
    output reg  [31:0] wb_alu_result,
    output reg  [31:0] wb_rdata,
    output reg  [4:0]  wb_rd,

    // Control Outputs to WB Stage
    output reg         wb_reg_write,
    output reg  [1:0]  wb_wb_sel
);

    initial begin
        wb_pc         = 32'd0;
        wb_pc_plus4   = 32'd0;
        wb_alu_result = 32'd0;
        wb_rdata      = 32'd0;
        wb_rd         = 5'd0;
        wb_reg_write  = 1'b0;
        wb_wb_sel     = 2'b00;
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            wb_pc         <= 32'd0;
            wb_pc_plus4   <= 32'd0;
            wb_alu_result <= 32'd0;
            wb_rdata      <= 32'd0;
            wb_rd         <= 5'd0;
            wb_reg_write  <= 1'b0;
            wb_wb_sel     <= 2'b00;
        end else if (flush) begin
            wb_pc         <= 32'd0;
            wb_pc_plus4   <= 32'd0;
            wb_alu_result <= 32'd0;
            wb_rdata      <= 32'd0;
            wb_rd         <= 5'd0;
            wb_reg_write  <= 1'b0;
            wb_wb_sel     <= 2'b00;
        end else if (!stall) begin
            wb_pc         <= mem_pc;
            wb_pc_plus4   <= mem_pc_plus4;
            wb_alu_result <= mem_alu_result;
            wb_rdata      <= mem_rdata;
            wb_rd         <= mem_rd;
            wb_reg_write  <= mem_reg_write;
            wb_wb_sel     <= mem_wb_sel;
        end
    end

endmodule
