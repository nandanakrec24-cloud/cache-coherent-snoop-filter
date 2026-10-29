`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// Unit testbench for l1_cache.
// The testbench plays the role of the core AND of the coherence controller:
//   * a small "fake controller" answers miss requests (fill) and writebacks
//   * tasks drive core reads/writes and snoops
// -----------------------------------------------------------------------------
module tb_l1_cache;

    localparam [1:0] ST_I = 2'b00, ST_S = 2'b01, ST_E = 2'b10, ST_M = 2'b11;
    localparam [1:0] REQ_READ = 2'b00, REQ_RDX = 2'b01, REQ_UPGRADE = 2'b10;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    // Core side
    reg         core_req_valid = 1'b0;
    reg         core_req_write = 1'b0;
    reg  [15:0] core_req_addr  = 16'h0;
    reg  [31:0] core_req_wdata = 32'h0;
    wire        core_req_ready;
    wire        core_resp_valid;
    wire [31:0] core_resp_rdata;

    // Miss / fill
    wire        miss_req_valid;
    wire [1:0]  miss_req_type;
    wire [15:0] miss_req_addr;
    reg         fill_valid = 1'b0;
    reg  [31:0] fill_data  = 32'h0;
    reg  [1:0]  fill_state = ST_E;

    // Writeback
    wire        wb_req_valid;
    wire [15:0] wb_req_addr;
    wire [31:0] wb_req_data;
    reg         wb_ack = 1'b0;

    // Snoop
    reg         snoop_valid      = 1'b0;
    reg  [15:0] snoop_addr       = 16'h0;
    reg         snoop_invalidate = 1'b0;
    wire        snoop_hit;
    wire [1:0]  snoop_state;
    wire [31:0] snoop_data;

    l1_cache dut (
        .clk(clk), .rst_n(rst_n),
        .core_req_valid(core_req_valid), .core_req_write(core_req_write),
        .core_req_addr(core_req_addr), .core_req_wdata(core_req_wdata),
        .core_req_ready(core_req_ready), .core_resp_valid(core_resp_valid),
        .core_resp_rdata(core_resp_rdata),
        .miss_req_valid(miss_req_valid), .miss_req_type(miss_req_type),
        .miss_req_addr(miss_req_addr), .fill_valid(fill_valid),
        .fill_data(fill_data), .fill_state(fill_state),
        .wb_req_valid(wb_req_valid), .wb_req_addr(wb_req_addr),
        .wb_req_data(wb_req_data), .wb_ack(wb_ack),
        .snoop_valid(snoop_valid), .snoop_addr(snoop_addr),
        .snoop_invalidate(snoop_invalidate), .snoop_hit(snoop_hit),
        .snoop_state(snoop_state), .snoop_data(snoop_data)
    );

    // ---------------- Fake memory + controller ----------------
    reg  [31:0] mem [0:65535];
    reg  [1:0]  next_fill_state = ST_E;  // state the fake controller grants on READ
    reg  [2:0]  miss_timer = 3'd0;
    integer     miss_count = 0;
    integer     wb_count   = 0;
    reg  [1:0]  last_miss_type;
    reg  [15:0] last_wb_addr;
    reg  [31:0] last_wb_data;
    integer     errors = 0;
    integer     k;

    initial for (k = 0; k < 65536; k = k + 1) mem[k] = {16'hA5A5, k[15:0]};

    always @(posedge clk) begin
        fill_valid <= 1'b0;
        wb_ack     <= 1'b0;

        // Miss: answer 3 cycles after the request appears
        if (miss_req_valid && !fill_valid) begin
            if (miss_timer == 0) begin
                miss_timer     <= 3'd3;
                miss_count     = miss_count + 1;
                last_miss_type <= miss_req_type;
            end else if (miss_timer == 1) begin
                fill_valid <= 1'b1;
                fill_data  <= mem[miss_req_addr];
                fill_state <= next_fill_state;
                miss_timer <= 3'd0;
            end else begin
                miss_timer <= miss_timer - 1;
            end
        end

        // Writeback: accept in one cycle
        if (wb_req_valid && !wb_ack) begin
            mem[wb_req_addr] <= wb_req_data;
            wb_ack           <= 1'b1;
            wb_count         = wb_count + 1;
            last_wb_addr     <= wb_req_addr;
            last_wb_data     <= wb_req_data;
        end
    end

    // ---------------- Helper tasks ----------------
    task core_access;
        input         write;
        input  [15:0] addr;
        input  [31:0] wdata;
        output [31:0] rdata;
        begin
            @(negedge clk);
            core_req_valid = 1'b1;
            core_req_write = write;
            core_req_addr  = addr;
            core_req_wdata = wdata;
            while (!core_req_ready) @(negedge clk);
            @(negedge clk);                 // accepted on the posedge in between
            core_req_valid = 1'b0;
            while (!core_resp_valid) @(negedge clk);
            rdata = core_resp_rdata;
        end
    endtask

    task snoop;
        input [15:0] addr;
        input        inval;
        begin
            @(negedge clk);
            snoop_valid      = 1'b1;
            snoop_addr       = addr;
            snoop_invalidate = inval;
            @(negedge clk);
            snoop_valid      = 1'b0;
            snoop_invalidate = 1'b0;
        end
    endtask

    task expect_eq;
        input [255:0] what;   // short label
        input [31:0]  got;
        input [31:0]  exp;
        begin
            if (got !== exp) begin
                $display("FAIL %0s: expected %h got %h", what, exp, got);
                errors = errors + 1;
            end
        end
    endtask

    reg [31:0] rd;
    integer    m0, w0;

    initial begin
        $dumpfile("build/l1_cache.vcd");
        $dumpvars(0, tb_l1_cache);
        $display("Starting l1_cache tests");

        repeat (2) @(negedge clk);
        rst_n = 1'b1;

        // 1. Reset: every line Invalid
        for (k = 0; k < 8; k = k + 1)
            expect_eq("reset state", dut.state_mem[k], ST_I);

        // 2. Read miss -> READ request, install in E
        next_fill_state = ST_E;
        m0 = miss_count;
        core_access(0, 16'h0010, 0, rd);
        expect_eq("T2 miss count", miss_count - m0, 1);
        expect_eq("T2 miss type",  last_miss_type, REQ_READ);
        expect_eq("T2 read data",  rd, 32'hA5A50010);
        expect_eq("T2 state",      dut.state_mem[0], ST_E);

        // 3. Read hit -> no new miss
        m0 = miss_count;
        core_access(0, 16'h0010, 0, rd);
        expect_eq("T3 no miss", miss_count - m0, 0);
        expect_eq("T3 data",    rd, 32'hA5A50010);

        // 4. Write hit in E -> silent upgrade to M, no bus traffic
        m0 = miss_count;
        core_access(1, 16'h0010, 32'h11111111, rd);
        expect_eq("T4 no miss", miss_count - m0, 0);
        expect_eq("T4 state",   dut.state_mem[0], ST_M);
        core_access(0, 16'h0010, 0, rd);
        expect_eq("T4 readback", rd, 32'h11111111);

        // 5. Conflict miss on dirty line -> writeback, then READ, install in S
        next_fill_state = ST_S;
        w0 = wb_count; m0 = miss_count;
        core_access(0, 16'h0018, 0, rd);    // same index 0, different tag
        expect_eq("T5 wb count", wb_count - w0, 1);
        expect_eq("T5 wb addr",  last_wb_addr, 16'h0010);
        expect_eq("T5 wb data",  last_wb_data, 32'h11111111);
        expect_eq("T5 mem",      mem[16'h0010], 32'h11111111);
        expect_eq("T5 miss",     miss_count - m0, 1);
        expect_eq("T5 data",     rd, 32'hA5A50018);
        expect_eq("T5 state",    dut.state_mem[0], ST_S);

        // 6. Write hit in S -> UPGRADE request, then M
        m0 = miss_count;
        core_access(1, 16'h0018, 32'h22222222, rd);
        expect_eq("T6 miss",  miss_count - m0, 1);
        expect_eq("T6 type",  last_miss_type, REQ_UPGRADE);
        expect_eq("T6 state", dut.state_mem[0], ST_M);
        core_access(0, 16'h0018, 0, rd);
        expect_eq("T6 readback", rd, 32'h22222222);

        // 7. Write miss -> RDX, then M with written data
        m0 = miss_count;
        core_access(1, 16'h0021, 32'h33333333, rd);   // index 1
        expect_eq("T7 type",  last_miss_type, REQ_RDX);
        expect_eq("T7 state", dut.state_mem[1], ST_M);
        core_access(0, 16'h0021, 0, rd);
        expect_eq("T7 readback", rd, 32'h33333333);

        // 8. Read snoop on M line -> hit, report M + data, become S
        @(negedge clk);
        snoop_addr = 16'h0021; snoop_invalidate = 1'b0; snoop_valid = 1'b1;
        #1;
        expect_eq("T8 snoop hit",   snoop_hit, 1);
        expect_eq("T8 snoop state", snoop_state, ST_M);
        expect_eq("T8 snoop data",  snoop_data, 32'h33333333);
        @(negedge clk); snoop_valid = 1'b0;
        expect_eq("T8 new state", dut.state_mem[1], ST_S);

        // 9. Invalidating snoop -> I; next read misses
        snoop(16'h0021, 1'b1);
        expect_eq("T9 state", dut.state_mem[1], ST_I);
        m0 = miss_count;
        next_fill_state = ST_E;
        core_access(0, 16'h0021, 0, rd);
        expect_eq("T9 refetch miss", miss_count - m0, 1);

        // 10. Snoop to an address we don't hold -> no hit, no change
        @(negedge clk);
        snoop_addr = 16'h0099; snoop_invalidate = 1'b1; snoop_valid = 1'b1;
        #1;
        expect_eq("T10 no hit", snoop_hit, 0);
        expect_eq("T10 state",  snoop_state, ST_I);
        @(negedge clk); snoop_valid = 1'b0;
        expect_eq("T10 line1 kept", dut.state_mem[1], ST_E);

        // 11. Race: line in S, core writes (UPGRADE), other core invalidates
        //     us while we wait. Fill supplies data; result must still be M
        //     with the core's written value.
        next_fill_state = ST_S;
        core_access(0, 16'h0032, 0, rd);           // index 2, now S
        expect_eq("T11 setup S", dut.state_mem[2], ST_S);
        fork
            core_access(1, 16'h0032, 32'h44444444, rd);
            begin
                wait (miss_req_valid);
                snoop(16'h0032, 1'b1);
            end
        join
        expect_eq("T11 state", dut.state_mem[2], ST_M);
        core_access(0, 16'h0032, 0, rd);
        expect_eq("T11 data",  rd, 32'h44444444);

        // 12. Core is stalled while a snoop is active
        @(negedge clk);
        snoop_valid = 1'b1; snoop_addr = 16'h0099;
        #1;
        expect_eq("T12 ready low", core_req_ready, 0);
        @(negedge clk); snoop_valid = 1'b0;

        if (errors == 0) begin
            $display("PASS: all l1_cache checks passed");
            $finish;
        end else begin
            $display("FAIL: %0d check(s) failed", errors);
            $fatal(1);
        end
    end

    // Safety net: never hang forever
    initial begin
        #20000;
        $display("FAIL: timeout");
        $fatal(1);
    end

endmodule
