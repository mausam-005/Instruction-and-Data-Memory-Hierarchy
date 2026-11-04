`timescale 1ns / 1ps
// =============================================================================
// Module: mem_arbiter
// Description:
//   Bus Arbiter FSM resolving structural contention between Instruction Fetch
//   and Data Memory Load/Store in the baseline Von Neumann architecture.
//   Because both instruction and data share a single physical memory port,
//   concurrent requests cannot be satisfied simultaneously.
//
//   Arbitration Policy:
//     - When only Instruction Fetch requests: Grant Instruction (0 stall).
//     - When only Data Load/Store requests: Grant Data (0 stall).
//     - When BOTH collide in the same cycle:
//         1. Grant Data Port first (grant_data = 1, grant_instr = 0).
//         2. Assert stall = 1 to freeze the CPU / Instruction Fetch stage.
//         3. In the subsequent cycle, serve the stalled Instruction Fetch
//            (grant_instr = 1, grant_data = 0, stall = 0).
//
//   FSM States:
//     - IDLE        (2'b00) : No contention or idle bus state.
//     - SERVE_DATA  (2'b01) : Currently servicing data memory access.
//     - SERVE_INSTR (2'b10) : Servicing stalled / pending instruction fetch.
// =============================================================================

module mem_arbiter #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32
)(
    input  wire                  clk,
    input  wire                  rst,

    // Instruction Port (Fetch Path)
    input  wire                  instr_read_en,
    input  wire [ADDR_WIDTH-1:0] instr_addr,
    output wire [DATA_WIDTH-1:0] instr_data,

    // Data Port (Load / Store Path)
    input  wire                  data_read_en,
    input  wire                  data_write_en,
    input  wire [3:0]            data_byte_enable,
    input  wire [ADDR_WIDTH-1:0] data_addr,
    input  wire [DATA_WIDTH-1:0] data_wdata,
    output wire [DATA_WIDTH-1:0] data_rdata,

    // Arbiter Control and Status
    output wire                  grant_instr,
    output wire                  grant_data,
    output wire [1:0]            arb_state,
    output wire                  stall,

    // Unified Memory Interface
    output wire                  mem_read,
    output wire                  mem_write,
    output wire [3:0]            mem_byte_enable,
    output wire [ADDR_WIDTH-1:0] mem_addr,
    output wire [DATA_WIDTH-1:0] mem_wdata,
    input  wire [DATA_WIDTH-1:0] mem_rdata
);

    // State Encoding
    localparam [1:0] IDLE        = 2'b00;
    localparam [1:0] SERVE_DATA  = 2'b01;
    localparam [1:0] SERVE_INSTR = 2'b10;

    // Internal request generation
    wire data_req    = data_read_en | data_write_en;
    wire instr_req   = instr_read_en;
    wire contention  = instr_req & data_req;

    // FSM State Registers
    reg [1:0] state_reg, next_state;

    // Synchronous FSM State Update
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state_reg <= IDLE;
        end else begin
            state_reg <= next_state;
        end
    end

    // Next-State Logic
    always @(*) begin
        case (state_reg)
            IDLE: begin
                if (contention) begin
                    // Structural hazard detected: serve data first, then serve instruction next cycle
                    next_state = SERVE_INSTR;
                end else if (data_req) begin
                    next_state = SERVE_DATA;
                end else begin
                    next_state = IDLE;
                end
            end

            SERVE_DATA: begin
                if (contention) begin
                    next_state = SERVE_INSTR;
                end else if (data_req) begin
                    next_state = SERVE_DATA;
                end else begin
                    next_state = IDLE;
                end
            end

            SERVE_INSTR: begin
                // Stalled instruction fetch has been served during this cycle.
                // Check if new contention or requests arrive for the next cycle.
                if (contention) begin
                    next_state = SERVE_INSTR;
                end else if (data_req) begin
                    next_state = SERVE_DATA;
                end else begin
                    next_state = IDLE;
                end
            end

            default: begin
                next_state = IDLE;
            end
        endcase
    end

    // Combinational Bus Grant & Stall Generation
    // When state_reg == SERVE_INSTR, the arbiter is dedicated to completing the
    // deferred instruction fetch without being pre-empted by data.
    // In IDLE and SERVE_DATA, data has higher priority, and instruction is stalled on collision.
    assign grant_data  = (state_reg == SERVE_INSTR) ? 1'b0 : data_req;
    assign grant_instr = (state_reg == SERVE_INSTR) ? instr_req : (instr_req & ~data_req);
    assign stall       = (state_reg == SERVE_INSTR) ? 1'b0 : contention;

    // Arbiter Telemetry State
    assign arb_state   = grant_data  ? SERVE_DATA  :
                         grant_instr ? SERVE_INSTR :
                                       IDLE;

    // Multiplexed Unified Memory Signals
    assign mem_read        = grant_data ? data_read_en : (grant_instr ? instr_read_en : 1'b0);
    assign mem_write       = grant_data ? data_write_en : 1'b0;
    assign mem_byte_enable = grant_data ? data_byte_enable : 4'b1111;
    assign mem_addr        = grant_data ? data_addr : (grant_instr ? instr_addr : {ADDR_WIDTH{1'b0}});
    assign mem_wdata       = data_wdata;

    // Demultiplexed Read Data
    assign instr_data = grant_instr ? mem_rdata : {DATA_WIDTH{1'b0}};
    assign data_rdata = grant_data  ? mem_rdata : {DATA_WIDTH{1'b0}};

endmodule

