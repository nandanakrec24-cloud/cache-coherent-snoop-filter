`timescale 1ns/1ps
`include "mesi_defs.vh"

module tb_mesi_controller;
    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;

    reg c0_miss_valid = 0, c1_miss_valid = 0;
    reg [1:0] c0_miss_type = `MISS_READ, c1_miss_type = `MISS_READ;
    reg [15:0] c0_miss_addr = 0, c1_miss_addr = 0;
    wire c0_fill_valid, c1_fill_valid;
    wire [31:0] c0_fill_data, c1_fill_data;
    wire [1:0] c0_fill_state, c1_fill_state;

    reg c0_wb_valid = 0, c1_wb_valid = 0;
    reg [15:0] c0_wb_addr = 0, c1_wb_addr = 0;
    reg [31:0] c0_wb_data = 0, c1_wb_data = 0;
    wire c0_wb_ack, c1_wb_ack;

    wire c0_snoop_valid, c1_snoop_valid;
    wire [15:0] c0_snoop_addr, c1_snoop_addr;
    wire c0_snoop_invalidate, c1_snoop_invalidate;
    reg c0_snoop_hit = 0, c1_snoop_hit = 0;
    reg [1:0] c0_snoop_state = `MESI_I, c1_snoop_state = `MESI_I;
    reg [31:0] c0_snoop_data = 0, c1_snoop_data = 0;

    wire mem_req_valid, mem_req_write;
    wire [15:0] mem_req_addr;
    wire [31:0] mem_req_wdata;
    reg mem_req_ready = 1;
    reg mem_resp_valid = 0;
    reg [31:0] mem_resp_rdata = 0;

    wire [15:0] filter_query_addr, filter_remove_addr, filter_insert_addr;
    reg filter_hit = 0;
    wire filter_remove_valid, filter_insert_absent, filter_clear_all;
    reg known_absent_insert_valid = 0;
    reg [15:0] known_absent_insert_addr = 0;
    wire busy;

    integer errors = 0;
    integer cycles;
    integer mem_write_accept_count = 0;
    integer mem_read_accept_count = 0;
    integer c0_fill_count = 0;
    integer c1_fill_count = 0;
    integer writes_before;
    integer reads_before;
    integer fills_before;
    integer j;

    always @(posedge clk) begin
        if (rst_n) begin
            if (mem_req_valid && mem_req_ready && mem_req_write)
                mem_write_accept_count <= mem_write_accept_count + 1;
            if (mem_req_valid && mem_req_ready && !mem_req_write)
                mem_read_accept_count <= mem_read_accept_count + 1;
            if (c0_fill_valid) c0_fill_count <= c0_fill_count + 1;
            if (c1_fill_valid) c1_fill_count <= c1_fill_count + 1;
        end
    end

    mesi_controller dut (
        .clk(clk), .rst_n(rst_n),
        .c0_miss_valid(c0_miss_valid), .c0_miss_type(c0_miss_type), .c0_miss_addr(c0_miss_addr),
        .c0_fill_valid(c0_fill_valid), .c0_fill_data(c0_fill_data), .c0_fill_state(c0_fill_state),
        .c1_miss_valid(c1_miss_valid), .c1_miss_type(c1_miss_type), .c1_miss_addr(c1_miss_addr),
        .c1_fill_valid(c1_fill_valid), .c1_fill_data(c1_fill_data), .c1_fill_state(c1_fill_state),
        .c0_wb_valid(c0_wb_valid), .c0_wb_addr(c0_wb_addr), .c0_wb_data(c0_wb_data), .c0_wb_ack(c0_wb_ack),
        .c1_wb_valid(c1_wb_valid), .c1_wb_addr(c1_wb_addr), .c1_wb_data(c1_wb_data), .c1_wb_ack(c1_wb_ack),
        .c0_snoop_valid(c0_snoop_valid), .c0_snoop_addr(c0_snoop_addr), .c0_snoop_invalidate(c0_snoop_invalidate),
        .c0_snoop_hit(c0_snoop_hit), .c0_snoop_state(c0_snoop_state), .c0_snoop_data(c0_snoop_data),
        .c1_snoop_valid(c1_snoop_valid), .c1_snoop_addr(c1_snoop_addr), .c1_snoop_invalidate(c1_snoop_invalidate),
        .c1_snoop_hit(c1_snoop_hit), .c1_snoop_state(c1_snoop_state), .c1_snoop_data(c1_snoop_data),
        .mem_req_valid(mem_req_valid), .mem_req_write(mem_req_write), .mem_req_addr(mem_req_addr),
        .mem_req_wdata(mem_req_wdata), .mem_req_ready(mem_req_ready),
        .mem_resp_valid(mem_resp_valid), .mem_resp_rdata(mem_resp_rdata),
        .filter_query_addr(filter_query_addr), .filter_hit(filter_hit),
        .filter_remove_valid(filter_remove_valid), .filter_remove_addr(filter_remove_addr),
        .known_absent_insert_valid(known_absent_insert_valid),
        .known_absent_insert_addr(known_absent_insert_addr),
        .filter_insert_absent(filter_insert_absent), .filter_insert_addr(filter_insert_addr),
        .filter_clear_all(filter_clear_all), .busy(busy)
    );

    task check;
        input [1023:0] label;
        input condition;
        begin
            if (condition !== 1'b1) begin
                $display("FAIL: %0s", label);
                errors = errors + 1;
            end
        end
    endtask

    task wait_fill0;
        integer t;
        begin
            t = 0;
            while (!c0_fill_valid && t < 20) begin @(posedge clk); #1; t = t + 1; end
            check("timeout waiting for c0 fill", c0_fill_valid);
        end
    endtask

    task wait_fill1;
        integer t;
        begin
            t = 0;
            while (!c1_fill_valid && t < 20) begin @(posedge clk); #1; t = t + 1; end
            check("timeout waiting for c1 fill", c1_fill_valid);
        end
    endtask

    task test_clean_peer_read;
        input [1:0] peer_state;
        input [15:0] addr;
        integer accepted_writes;
        begin
            @(negedge clk);
            filter_hit = 0;
            c1_snoop_hit = 1;
            c1_snoop_state = peer_state;
            c0_miss_addr = addr;
            c0_miss_type = `MISS_READ;
            c0_miss_valid = 1;
            accepted_writes = mem_write_accept_count;

            @(negedge clk);
            c0_miss_valid = 0;
            wait (c1_snoop_valid);
            check("clean peer READ snoop does not invalidate", !c1_snoop_invalidate);
            @(posedge clk); #1;
            check("clean peer READ uses memory read", mem_req_valid && !mem_req_write && mem_req_addr == addr);
            @(posedge clk); #1;
            @(negedge clk); mem_resp_rdata = 32'hBEEF0000 | addr; mem_resp_valid = 1;
            @(posedge clk); #1;
            check("clean peer READ fills Shared", c0_fill_valid && c0_fill_state == `MESI_S);
            check("clean peer READ data comes from memory", c0_fill_data == (32'hBEEF0000 | addr));
            check("clean peer READ does not write memory", mem_write_accept_count == accepted_writes);
            @(negedge clk); mem_resp_valid = 0; c1_snoop_hit = 0; c1_snoop_state = `MESI_I;
            @(posedge clk); #1;
        end
    endtask

    initial begin
        $dumpfile("/tmp/mesi_controller.vcd");
        $dumpvars(0, tb_mesi_controller);
        repeat (2) @(negedge clk);
        rst_n = 1;

        // Test 1: filter hit on READ safely skips snoop; memory supplies data.
        @(negedge clk);
        filter_hit = 1;
        c0_miss_addr = 16'h0010;
        c0_miss_type = `MISS_READ;
        c0_miss_valid = 1;
        mem_req_ready = 0;
        reads_before = mem_read_accept_count;
        #1;
        check("filter query follows selected address", filter_query_addr == 16'h0010);
        check("accepted miss removes stale negative entry", filter_remove_valid && filter_remove_addr == 16'h0010);
        @(negedge clk); c0_miss_valid = 0;
        wait (mem_req_valid);
        check("read command is held valid under backpressure", mem_req_valid && !mem_req_write);
        check("memory read address is requested address", mem_req_addr == 16'h0010);
        for (j = 0; j < 3; j = j + 1) begin
            @(posedge clk); #1;
            check("memory read request remains valid while stalled", mem_req_valid && !mem_req_write);
            check("memory read address remains stable", mem_req_addr == 16'h0010);
            check("memory read does not fill before acceptance", !c0_fill_valid);
        end
        @(negedge clk); mem_req_ready = 1;
        @(posedge clk); #1;
        check("memory read is accepted exactly once", mem_read_accept_count == reads_before + 1);
        check("memory read request drops after acceptance", !mem_req_valid);
        @(negedge clk); mem_resp_rdata = 32'hA5A50010; mem_resp_valid = 1;
        @(negedge clk); mem_resp_valid = 0;
        wait_fill0;
        check("READ data from memory", c0_fill_data == 32'hA5A50010);
        check("READ without peer copy gets E", c0_fill_state == `MESI_E);
        @(negedge clk);

        // Test 2: RDX snoops a peer in M and forwards its latest data.
        filter_hit = 0;
        c1_miss_addr = 16'h0020;
        c1_miss_type = `MISS_RDX;
        c0_snoop_hit = 1;
        c0_snoop_state = `MESI_M;
        c0_snoop_data = 32'hDEADBEEF;
        c1_miss_valid = 1;
        @(negedge clk); c1_miss_valid = 0;
        wait (c0_snoop_valid);
        check("RDX sends invalidating snoop", c0_snoop_invalidate == 1);
        wait_fill1;
        check("M owner data forwarded", c1_fill_data == 32'hDEADBEEF);
        check("RDX grants M", c1_fill_state == `MESI_M);
        @(negedge clk); c0_snoop_hit = 0; c0_snoop_state = `MESI_I;

        // Test 3: READ of peer M invalidates it, writes dirty data once, and
        // withholds the Shared fill until memory accepts the write.
        @(negedge clk);
        c0_snoop_hit = 1;
        c0_snoop_state = `MESI_M;
        c0_snoop_data = 32'hD1A7CAFE;
        c1_miss_addr = 16'h0028;
        c1_miss_type = `MISS_READ;
        c1_miss_valid = 1;
        mem_req_ready = 0;
        writes_before = mem_write_accept_count;
        fills_before = c1_fill_count;
        @(negedge clk); c1_miss_valid = 0;
        wait (c0_snoop_valid);
        check("READ snoop invalidates peer M", c0_snoop_invalidate);
        check("READ does not invalidate requester", !c1_snoop_invalidate);
        wait (mem_req_valid);
        check("dirty READ issues memory write", mem_req_write && mem_req_addr == 16'h0028 && mem_req_wdata == 32'hD1A7CAFE);
        check("dirty READ does not fill before write acceptance", !c1_fill_valid);
        for (j = 0; j < 3; j = j + 1) begin
            @(posedge clk); #1;
            check("dirty write remains valid under backpressure", mem_req_valid && mem_req_write);
            check("dirty write address stays stable", mem_req_addr == 16'h0028);
            check("dirty write data stays stable", mem_req_wdata == 32'hD1A7CAFE);
            check("dirty READ remains unfilled under backpressure", !c1_fill_valid);
        end
        @(negedge clk); mem_req_ready = 1;
        @(posedge clk); #1;
        check("dirty write accepted exactly once", mem_write_accept_count == writes_before + 1);
        check("dirty READ fills after write acceptance", c1_fill_valid);
        check("dirty READ fill carries snooped data", c1_fill_data == 32'hD1A7CAFE);
        check("dirty READ fill state is Shared", c1_fill_state == `MESI_S);
        @(posedge clk); #1;
        check("dirty READ produces exactly one fill", c1_fill_count == fills_before + 1);
        check("dirty READ does not repeat memory write", mem_write_accept_count == writes_before + 1);
        check("dirty READ fill pulse ends", !c1_fill_valid);
        @(negedge clk); c0_snoop_hit = 0; c0_snoop_state = `MESI_I;

        // READs from clean peer S and E still use memory and grant Shared,
        // without issuing a memory write or invalidating the peer.
        test_clean_peer_read(`MESI_S, 16'h0030);
        test_clean_peer_read(`MESI_E, 16'h0034);

        // Test 4: dirty writeback is forwarded and acknowledged after acceptance.
        @(negedge clk);
        c0_wb_valid = 1; c0_wb_addr = 16'h0038; c0_wb_data = 32'hCAFEBABE;
        wait (mem_req_valid);
        check("writeback command is write", mem_req_write == 1);
        check("writeback address preserved", mem_req_addr == 16'h0038);
        check("writeback data preserved", mem_req_wdata == 32'hCAFEBABE);
        wait (c0_wb_ack);
        @(negedge clk); c0_wb_valid = 0;

        // Test 5: externally proven absent event is passed to the filter.
        known_absent_insert_valid = 1;
        known_absent_insert_addr = 16'h0044;
        #1;
        check("known-absent insert forwarded", filter_insert_absent && filter_insert_addr == 16'h0044);
        @(negedge clk); known_absent_insert_valid = 0;

        if (errors == 0) begin
            $display("PASS: all MESI controller unit checks passed");
            $finish;
        end else begin
            $display("FAIL: %0d MESI controller check(s) failed", errors);
            $fatal(1);
        end
    end

    initial begin
        #10000;
        $display("FAIL: testbench timeout");
        $fatal(1);
    end
endmodule
