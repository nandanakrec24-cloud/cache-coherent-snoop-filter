`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// l1_cache : private, direct-mapped L1 cache with MESI state per line
//
// One instance per core. Talks to:
//   * the core        (core_req_* / core_resp_*)
//   * the controller  (miss_req_* / fill_*   : "I missed, please help")
//                     (wb_req_*  / wb_ack    : "write this dirty line back")
//                     (snoop_*               : "the other core wants this")
//
// Address split (16-bit word address, 8 lines):
//   [2:0]  index  -> which line
//   [15:3] tag    -> which address is stored in that line
//
// MESI encoding: I=00, S=01, E=10, M=11
// Miss request types: READ=00, RDX (read-for-ownership)=01, UPGRADE=10
// -----------------------------------------------------------------------------
module l1_cache #(
    parameter ADDR_WIDTH = 16,
    parameter DATA_WIDTH = 32,
    parameter NUM_LINES  = 8
) (
    input  wire                  clk,
    input  wire                  rst_n,

    // ---------------- Core side ----------------
    input  wire                  core_req_valid,
    input  wire                  core_req_write,   // 1 = write, 0 = read
    input  wire [ADDR_WIDTH-1:0] core_req_addr,
    input  wire [DATA_WIDTH-1:0] core_req_wdata,
    output wire                  core_req_ready,   // request accepted on a clock edge when valid && ready
    output reg                   core_resp_valid,  // one-cycle pulse when the request is finished
    output reg  [DATA_WIDTH-1:0] core_resp_rdata,  // read data (valid with core_resp_valid on reads)

    // ---------------- Miss / fill (to controller) ----------------
    output wire                  miss_req_valid,   // held high until fill_valid
    output wire [1:0]            miss_req_type,
    output wire [ADDR_WIDTH-1:0] miss_req_addr,
    input  wire                  fill_valid,       // one-cycle pulse from controller
    input  wire [DATA_WIDTH-1:0] fill_data,
    input  wire [1:0]            fill_state,       // E or S for READ; ignored for RDX/UPGRADE (line becomes M)

    // ---------------- Writeback (to controller) ----------------
    output wire                  wb_req_valid,     // held high until wb_ack
    output reg  [ADDR_WIDTH-1:0] wb_req_addr,
    output reg  [DATA_WIDTH-1:0] wb_req_data,
    input  wire                  wb_ack,           // one-cycle pulse from controller

    // ---------------- Snoop (from controller) ----------------
    input  wire                  snoop_valid,      // one-cycle request
    input  wire [ADDR_WIDTH-1:0] snoop_addr,
    input  wire                  snoop_invalidate, // 1 = drop the line, 0 = read snoop (M/E -> S)
    output wire                  snoop_hit,        // combinational
    output wire [1:0]            snoop_state,      // state BEFORE the snoop takes effect
    output wire [DATA_WIDTH-1:0] snoop_data        // line data (meaningful when snoop_state == M)
);

    localparam INDEX_BITS = $clog2(NUM_LINES);
    localparam TAG_BITS   = ADDR_WIDTH - INDEX_BITS;

    localparam [1:0] ST_I = 2'b00, ST_S = 2'b01, ST_E = 2'b10, ST_M = 2'b11;
    localparam [1:0] REQ_READ = 2'b00, REQ_RDX = 2'b01, REQ_UPGRADE = 2'b10;
    localparam [1:0] F_IDLE = 2'd0, F_WB = 2'd1, F_MISS = 2'd2;

    // ---------------- Storage ----------------
    reg [TAG_BITS-1:0]   tag_mem   [0:NUM_LINES-1];
    reg [DATA_WIDTH-1:0] data_mem  [0:NUM_LINES-1];
    reg [1:0]            state_mem [0:NUM_LINES-1];

    // ---------------- Controller FSM + latched request ----------------
    reg [1:0]            fsm;
    reg                  r_write;
    reg [ADDR_WIDTH-1:0] r_addr;
    reg [DATA_WIDTH-1:0] r_wdata;
    reg [1:0]            r_type;

    wire [INDEX_BITS-1:0] r_index = r_addr[INDEX_BITS-1:0];
    wire [TAG_BITS-1:0]   r_tag   = r_addr[ADDR_WIDTH-1:INDEX_BITS];

    // ---------------- Core lookup (combinational) ----------------
    wire [INDEX_BITS-1:0] c_index = core_req_addr[INDEX_BITS-1:0];
    wire [TAG_BITS-1:0]   c_tag   = core_req_addr[ADDR_WIDTH-1:INDEX_BITS];
    wire [1:0]            c_state = state_mem[c_index];
    wire                  c_hit   = (c_state != ST_I) && (tag_mem[c_index] == c_tag);

    // ---------------- Snoop lookup (combinational) ----------------
    wire [INDEX_BITS-1:0] s_index = snoop_addr[INDEX_BITS-1:0];
    wire [TAG_BITS-1:0]   s_tag   = snoop_addr[ADDR_WIDTH-1:INDEX_BITS];

    assign snoop_hit   = (state_mem[s_index] != ST_I) && (tag_mem[s_index] == s_tag);
    assign snoop_state = snoop_hit ? state_mem[s_index] : ST_I;
    assign snoop_data  = data_mem[s_index];

    // ---------------- Handshake outputs ----------------
    // A snoop in the same cycle stalls the core so both never update one line together.
    assign core_req_ready = (fsm == F_IDLE) && !snoop_valid;
    assign miss_req_valid = (fsm == F_MISS);
    assign miss_req_type  = r_type;
    assign miss_req_addr  = r_addr;
    assign wb_req_valid   = (fsm == F_WB);

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fsm             <= F_IDLE;
            core_resp_valid <= 1'b0;
            core_resp_rdata <= {DATA_WIDTH{1'b0}};
            r_write         <= 1'b0;
            r_addr          <= {ADDR_WIDTH{1'b0}};
            r_wdata         <= {DATA_WIDTH{1'b0}};
            r_type          <= REQ_READ;
            wb_req_addr     <= {ADDR_WIDTH{1'b0}};
            wb_req_data     <= {DATA_WIDTH{1'b0}};
            for (i = 0; i < NUM_LINES; i = i + 1) begin
                state_mem[i] <= ST_I;
                tag_mem[i]   <= {TAG_BITS{1'b0}};
                data_mem[i]  <= {DATA_WIDTH{1'b0}};
            end
        end else begin
            core_resp_valid <= 1'b0;

            // ---- 1. Snoop state update ----
            // Written first so that FSM updates below (later in the block) win
            // in the rare same-cycle case (e.g. wb_ack), which is always safe.
            if (snoop_valid && snoop_hit) begin
                if (snoop_invalidate)
                    state_mem[s_index] <= ST_I;
                else if (state_mem[s_index] == ST_M || state_mem[s_index] == ST_E)
                    state_mem[s_index] <= ST_S;
            end

            // ---- 2. Request FSM ----
            case (fsm)
                F_IDLE: begin
                    if (core_req_valid && core_req_ready) begin
                        r_write <= core_req_write;
                        r_addr  <= core_req_addr;
                        r_wdata <= core_req_wdata;

                        if (c_hit) begin
                            if (!core_req_write) begin
                                // Read hit in M/E/S
                                core_resp_rdata <= data_mem[c_index];
                                core_resp_valid <= 1'b1;
                            end else if (c_state == ST_S) begin
                                // Write hit in S: other copies must be invalidated first
                                r_type <= REQ_UPGRADE;
                                fsm    <= F_MISS;
                            end else begin
                                // Write hit in M or E: write locally, become M
                                data_mem[c_index]  <= core_req_wdata;
                                state_mem[c_index] <= ST_M;
                                core_resp_valid    <= 1'b1;
                            end
                        end else begin
                            // Miss
                            r_type <= core_req_write ? REQ_RDX : REQ_READ;
                            if (c_state == ST_M) begin
                                // Victim is dirty: write it back before refilling
                                wb_req_addr <= {tag_mem[c_index], c_index};
                                wb_req_data <= data_mem[c_index];
                                fsm         <= F_WB;
                            end else begin
                                fsm <= F_MISS;
                            end
                        end
                    end
                end

                F_WB: begin
                    if (wb_ack) begin
                        state_mem[r_index] <= ST_I;   // memory now holds the data
                        fsm                <= F_MISS;
                    end
                end

                F_MISS: begin
                    if (fill_valid) begin
                        tag_mem[r_index] <= r_tag;

                        // UPGRADE keeps our own copy if it survived; if a snoop
                        // invalidated it meanwhile, the controller must supply
                        // the line in fill_data (treated as RDX).
                        if (!(r_type == REQ_UPGRADE &&
                              state_mem[r_index] != ST_I &&
                              tag_mem[r_index] == r_tag))
                            data_mem[r_index] <= fill_data;

                        if (r_write) begin
                            data_mem[r_index]  <= r_wdata;   // overrides fill_data
                            state_mem[r_index] <= ST_M;
                        end else begin
                            state_mem[r_index] <= fill_state;
                            core_resp_rdata    <= fill_data;
                        end

                        core_resp_valid <= 1'b1;
                        fsm             <= F_IDLE;
                    end
                end

                default: fsm <= F_IDLE;
            endcase
        end
    end

endmodule
