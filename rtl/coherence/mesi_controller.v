`timescale 1ns/1ps
`include "mesi_defs.vh"

// Two-cache MESI transaction controller (baseline proposal).
// One transaction is active at a time. This module sequences L1 miss/fill,
// snoop, writeback, and backing-memory handshakes. The top-level must connect
// these ports to two l1_cache instances, the memory/bus model, and snoop filter.
module mesi_controller #(
    parameter ADDR_WIDTH = 16,
    parameter DATA_WIDTH = 32
) (
    input  wire                  clk,
    input  wire                  rst_n,

    // L1 cache 0 miss/fill interface
    input  wire                  c0_miss_valid,
    input  wire [1:0]            c0_miss_type,
    input  wire [ADDR_WIDTH-1:0] c0_miss_addr,
    output reg                   c0_fill_valid,
    output reg  [DATA_WIDTH-1:0] c0_fill_data,
    output reg  [1:0]            c0_fill_state,
    // L1 cache 1 miss/fill interface
    input  wire                  c1_miss_valid,
    input  wire [1:0]            c1_miss_type,
    input  wire [ADDR_WIDTH-1:0] c1_miss_addr,
    output reg                   c1_fill_valid,
    output reg  [DATA_WIDTH-1:0] c1_fill_data,
    output reg  [1:0]            c1_fill_state,

    // L1 dirty-victim writeback interfaces
    input  wire                  c0_wb_valid,
    input  wire [ADDR_WIDTH-1:0] c0_wb_addr,
    input  wire [DATA_WIDTH-1:0] c0_wb_data,
    output reg                   c0_wb_ack,
    input  wire                  c1_wb_valid,
    input  wire [ADDR_WIDTH-1:0] c1_wb_addr,
    input  wire [DATA_WIDTH-1:0] c1_wb_data,
    output reg                   c1_wb_ack,

    // Snoop interface to both caches. snoop_hit/state/data are combinational
    // observations for snoop_addr; state changes on the edge when valid is high.
    output reg                   c0_snoop_valid,
    output reg  [ADDR_WIDTH-1:0] c0_snoop_addr,
    output reg                   c0_snoop_invalidate,
    input  wire                  c0_snoop_hit,
    input  wire [1:0]            c0_snoop_state,
    input  wire [DATA_WIDTH-1:0] c0_snoop_data,
    output reg                   c1_snoop_valid,
    output reg  [ADDR_WIDTH-1:0] c1_snoop_addr,
    output reg                   c1_snoop_invalidate,
    input  wire                  c1_snoop_hit,
    input  wire [1:0]            c1_snoop_state,
    input  wire [DATA_WIDTH-1:0] c1_snoop_data,

    // Backing memory / serialized bus request interface.
    // A write completes when mem_req_valid && mem_req_ready; reads then wait
    // for mem_resp_valid. The memory model must implement this contract.
    output reg                   mem_req_valid,
    output reg                   mem_req_write,
    output reg  [ADDR_WIDTH-1:0] mem_req_addr,
    output reg  [DATA_WIDTH-1:0] mem_req_wdata,
    input  wire                  mem_req_ready,
    input  wire                  mem_resp_valid,
    input  wire [DATA_WIDTH-1:0] mem_resp_rdata,

    // Exclusive negative snoop filter interface. filter_hit must correspond
    // to filter_query_addr. The integrator supplies insert events only when it
    // can prove the address is absent from BOTH caches and no grant is pending.
    output reg  [ADDR_WIDTH-1:0] filter_query_addr,
    input  wire                  filter_hit,
    output reg                   filter_remove_valid,
    output reg  [ADDR_WIDTH-1:0] filter_remove_addr,
    input  wire                  known_absent_insert_valid,
    input  wire [ADDR_WIDTH-1:0] known_absent_insert_addr,
    output wire                  filter_insert_absent,
    output wire [ADDR_WIDTH-1:0] filter_insert_addr,
    output reg                   filter_clear_all,

    output reg                   busy
);

    localparam [3:0] ST_IDLE     = 4'd0,
                     ST_SNOOP    = 4'd1,
                     ST_MEM_REQ  = 4'd2,
                     ST_MEM_WAIT = 4'd3,
                     ST_FILL     = 4'd4,
                     ST_WB_REQ   = 4'd5,
                     ST_WB_ACK   = 4'd6,
                     ST_SNOOP_WB_REQ = 4'd7;

    reg [3:0] state;
    reg       owner;             // 0 -> cache 0, 1 -> cache 1
    reg [ADDR_WIDTH-1:0] txn_addr;
    reg [1:0] txn_type;
    reg [DATA_WIDTH-1:0] fill_data_reg;
    reg [1:0] fill_state_reg;
    reg       use_snoop_data;
    reg       need_snoop;
    reg       snoop_was_hit;
    reg [1:0] snoop_old_state;
    reg [DATA_WIDTH-1:0] snoop_data_reg;
    reg       wb_owner;
    reg [ADDR_WIDTH-1:0] wb_addr_reg;
    reg [DATA_WIDTH-1:0] wb_data_reg;
    reg       requester_still_has_line;

    wire choose_c0 = c0_miss_valid && !c1_miss_valid;
    wire choose_c1 = c1_miss_valid && !c0_miss_valid;
    wire both_miss = c0_miss_valid && c1_miss_valid;
    wire selected_miss = c0_miss_valid || c1_miss_valid;
    wire selected_owner = choose_c1 ? 1'b1 : (choose_c0 ? 1'b0 : 1'b0);
    wire [ADDR_WIDTH-1:0] selected_addr = selected_owner ? c1_miss_addr : c0_miss_addr;
    wire [1:0] selected_type = selected_owner ? c1_miss_type : c0_miss_type;

    // The filter is only allowed to suppress a snoop for a READ/RDX miss.
    // UPGRADE implies the requester already has a copy, so a negative-filter
    // hit would violate the filter invariant and is deliberately not trusted.
    always @* begin
        filter_query_addr = txn_addr;
        if (state == ST_IDLE && selected_miss)
            filter_query_addr = selected_addr;
    end

    assign filter_insert_absent = known_absent_insert_valid;
    assign filter_insert_addr = known_absent_insert_addr;

    always @* begin
        busy = (state != ST_IDLE);
        c0_fill_valid = 1'b0;
        c1_fill_valid = 1'b0;
        c0_fill_data = fill_data_reg;
        c1_fill_data = fill_data_reg;
        c0_fill_state = fill_state_reg;
        c1_fill_state = fill_state_reg;

        c0_wb_ack = 1'b0;
        c1_wb_ack = 1'b0;

        c0_snoop_valid = 1'b0;
        c1_snoop_valid = 1'b0;
        c0_snoop_addr = txn_addr;
        c1_snoop_addr = txn_addr;
        c0_snoop_invalidate = (txn_type != `MISS_READ);
        c1_snoop_invalidate = (txn_type != `MISS_READ);

        mem_req_valid = 1'b0;
        mem_req_write = `MEM_READ;
        mem_req_addr = txn_addr;
        mem_req_wdata = {DATA_WIDTH{1'b0}};

        filter_remove_valid = 1'b0;
        filter_remove_addr = selected_addr;
        filter_clear_all = 1'b0;

        case (state)
            ST_SNOOP: begin
                // A READ of a peer's Modified line must invalidate that peer
                // while its dirty data is written back before Shared is granted.
                if (txn_type == `MISS_READ &&
                    (owner == 1'b0 ? (c1_snoop_hit && c1_snoop_state == `MESI_M) :
                                     (c0_snoop_hit && c0_snoop_state == `MESI_M))) begin
                    if (owner == 1'b0) c1_snoop_invalidate = 1'b1;
                    else               c0_snoop_invalidate = 1'b1;
                end
                if (owner == 1'b0) c1_snoop_valid = need_snoop;
                else               c0_snoop_valid = need_snoop;
            end
            ST_MEM_REQ: begin
                mem_req_valid = 1'b1;
                mem_req_write = `MEM_READ;
                mem_req_addr  = txn_addr;
            end
            ST_FILL: begin
                if (owner == 1'b0) c0_fill_valid = 1'b1;
                else               c1_fill_valid = 1'b1;
            end
            ST_WB_REQ: begin
                mem_req_valid = 1'b1;
                mem_req_write = `MEM_WRITE;
                mem_req_addr  = wb_addr_reg;
                mem_req_wdata = wb_data_reg;
            end
            ST_SNOOP_WB_REQ: begin
                mem_req_valid = 1'b1;
                mem_req_write = `MEM_WRITE;
                mem_req_addr  = txn_addr;
                mem_req_wdata = snoop_data_reg;
            end
            ST_WB_ACK: begin
                if (wb_owner == 1'b0) c0_wb_ack = 1'b1;
                else                 c1_wb_ack = 1'b1;
            end
            default: begin end
        endcase

        // Remove negative knowledge on the same edge the request is accepted.
        if (state == ST_IDLE && selected_miss) begin
            filter_remove_valid = 1'b1;
            filter_remove_addr = selected_addr;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            owner <= 1'b0;
            txn_addr <= {ADDR_WIDTH{1'b0}};
            txn_type <= `MISS_READ;
            fill_data_reg <= {DATA_WIDTH{1'b0}};
            fill_state_reg <= `MESI_E;
            use_snoop_data <= 1'b0;
            need_snoop <= 1'b0;
            snoop_was_hit <= 1'b0;
            snoop_old_state <= `MESI_I;
            snoop_data_reg <= {DATA_WIDTH{1'b0}};
            wb_owner <= 1'b0;
            wb_addr_reg <= {ADDR_WIDTH{1'b0}};
            wb_data_reg <= {DATA_WIDTH{1'b0}};
            requester_still_has_line <= 1'b0;
        end else begin
            case (state)
                ST_IDLE: begin
                    // Finish dirty writebacks before accepting a new miss.
                    if (c0_wb_valid || c1_wb_valid) begin
                        wb_owner <= c0_wb_valid ? 1'b0 : 1'b1;
                        wb_addr_reg <= c0_wb_valid ? c0_wb_addr : c1_wb_addr;
                        wb_data_reg <= c0_wb_valid ? c0_wb_data : c1_wb_data;
                        state <= ST_WB_REQ;
                    end else if (selected_miss) begin
                        owner <= selected_owner;
                        txn_addr <= selected_addr;
                        txn_type <= selected_type;
                        use_snoop_data <= 1'b0;
                        snoop_was_hit <= 1'b0;
                        snoop_old_state <= `MESI_I;
                        snoop_data_reg <= {DATA_WIDTH{1'b0}};
                        requester_still_has_line <= 1'b0; // sampled after txn_addr is registered in ST_SNOOP
                        // A filter hit is safe only for addresses known absent.
                        need_snoop <= (selected_type == `MISS_UPGRADE) ? 1'b1 : !filter_hit;
                        if ((selected_type != `MISS_UPGRADE) && filter_hit)
                            state <= ST_MEM_REQ;
                        else
                            state <= ST_SNOOP;
                    end
                end

                ST_SNOOP: begin
                    // Capture the peer's combinational response on the edge
                    // where the snoop pulse is asserted.
                    if (owner == 1'b0) begin
                        snoop_was_hit <= c1_snoop_hit;
                        snoop_old_state <= c1_snoop_state;
                        snoop_data_reg <= c1_snoop_data;
                        if (c1_snoop_hit && c1_snoop_state == `MESI_M) begin
                            use_snoop_data <= 1'b1;
                            fill_data_reg <= c1_snoop_data;
                        end
                    end else begin
                        snoop_was_hit <= c0_snoop_hit;
                        snoop_old_state <= c0_snoop_state;
                        snoop_data_reg <= c0_snoop_data;
                        if (c0_snoop_hit && c0_snoop_state == `MESI_M) begin
                            use_snoop_data <= 1'b1;
                            fill_data_reg <= c0_snoop_data;
                        end
                    end

                    // For READ, any peer copy means Shared. For RDX, the peer
                    // is invalidated. For UPGRADE, keep the requester's copy if
                    // present; if it vanished, fetch current data before grant.
                    if (txn_type == `MISS_READ) begin
                        if ((owner == 1'b0 ? c1_snoop_hit : c0_snoop_hit))
                            fill_state_reg <= `MESI_S;
                        else
                            fill_state_reg <= `MESI_E;
                    end else begin
                        fill_state_reg <= `MESI_M;
                    end

                    if ((owner == 1'b0 ? c1_snoop_hit : c0_snoop_hit) &&
                        (owner == 1'b0 ? c1_snoop_state : c0_snoop_state) == `MESI_M) begin
                        fill_data_reg <= owner ? c0_snoop_data : c1_snoop_data;
                        if (txn_type == `MISS_READ) begin
                            fill_state_reg <= `MESI_S;
                            state <= ST_SNOOP_WB_REQ;
                        end else begin
                            state <= ST_FILL;
                        end
                    end else if (txn_type == `MISS_UPGRADE && (owner ? c1_snoop_hit : c0_snoop_hit)) begin
                        // L1 retains its own clean line; fill_data is unused by
                        // the L1 for a surviving UPGRADE and its write data wins.
                        fill_data_reg <= {DATA_WIDTH{1'b0}};
                        state <= ST_FILL;
                    end else begin
                        state <= ST_MEM_REQ;
                    end
                end

                ST_MEM_REQ: begin
                    if (mem_req_ready) state <= ST_MEM_WAIT;
                end

                ST_MEM_WAIT: begin
                    if (mem_resp_valid) begin
                        fill_data_reg <= mem_resp_rdata;
                        if (txn_type == `MISS_READ) begin
                            // If a peer copy was observed, retain S; otherwise E.
                            fill_state_reg <= snoop_was_hit ? `MESI_S : `MESI_E;
                        end else begin
                            fill_state_reg <= `MESI_M;
                        end
                        state <= ST_FILL;
                    end
                end

                ST_FILL: begin
                    state <= ST_IDLE;
                end

                ST_WB_REQ: begin
                    if (mem_req_ready) state <= ST_WB_ACK;
                end

                // Writes complete on request acceptance; do not grant the
                // requester Shared until the dirty peer data is safely stored.
                ST_SNOOP_WB_REQ: begin
                    if (mem_req_ready) state <= ST_FILL;
                end

                ST_WB_ACK: begin
                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
