`timescale 1ns/1ps
`include "mesi_defs.vh"

module tb_mesi_l1_integration;

    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;

    // Core interfaces
    reg c0_req_valid = 0, c0_req_write = 0;
    reg [15:0] c0_req_addr = 0;
    reg [31:0] c0_req_wdata = 0;
    wire c0_req_ready, c0_resp_valid;
    wire [31:0] c0_resp_rdata;

    reg c1_req_valid = 0, c1_req_write = 0;
    reg [15:0] c1_req_addr = 0;
    reg [31:0] c1_req_wdata = 0;
    wire c1_req_ready, c1_resp_valid;
    wire [31:0] c1_resp_rdata;

    // L1 miss/fill interfaces
    wire c0_miss_valid, c1_miss_valid;
    wire [1:0] c0_miss_type, c1_miss_type;
    wire [15:0] c0_miss_addr, c1_miss_addr;
    wire c0_fill_valid, c1_fill_valid;
    wire [31:0] c0_fill_data, c1_fill_data;
    wire [1:0] c0_fill_state, c1_fill_state;

    // L1 writeback interfaces
    wire c0_wb_valid, c1_wb_valid;
    wire [15:0] c0_wb_addr, c1_wb_addr;
    wire [31:0] c0_wb_data, c1_wb_data;
    wire c0_wb_ack, c1_wb_ack;

    // L1 snoop interfaces
    wire c0_snoop_valid, c1_snoop_valid;
    wire [15:0] c0_snoop_addr, c1_snoop_addr;
    wire c0_snoop_invalidate, c1_snoop_invalidate;
    wire c0_snoop_hit, c1_snoop_hit;
    wire [1:0] c0_snoop_state, c1_snoop_state;
    wire [31:0] c0_snoop_data, c1_snoop_data;

    // Backing memory interface
    wire mem_req_valid, mem_req_write;
    wire [15:0] mem_req_addr;
    wire [31:0] mem_req_wdata;
    reg mem_req_ready = 1;
    reg mem_resp_valid = 0;
    reg [31:0] mem_resp_rdata = 0;

    reg [31:0] memory [0:65535];
    integer i;
    integer errors = 0;
    integer snoop_count = 0;

    always @(posedge clk) begin
        if (rst_n && (c0_snoop_valid || c1_snoop_valid))
            snoop_count <= snoop_count + 1;
    end

    // Real negative snoop filter
    wire [15:0] filter_query_addr;
    wire filter_hit;
    wire filter_remove_valid, filter_insert_absent, filter_clear_all;
    wire [15:0] filter_remove_addr, filter_insert_addr;
    reg known_absent_insert_valid = 0;
    reg [15:0] known_absent_insert_addr = 0;
    wire busy;

    snoop_filter #(
        .ADDR_WIDTH(16),
        .FILTER_ENTRIES(4)
    ) filter_inst (
        .clk(clk),
        .rst_n(rst_n),
        .query_addr(filter_query_addr),
        .filter_hit(filter_hit),
        .snoop_required(),
        .insert_absent(filter_insert_absent),
        .insert_addr(filter_insert_addr),
        .remove_addr_valid(filter_remove_valid),
        .remove_addr(filter_remove_addr),
        .clear_all(filter_clear_all)
    );

    // MESI controller
    mesi_controller dut (
        .clk(clk), .rst_n(rst_n),
        .c0_miss_valid(c0_miss_valid),
        .c0_miss_type(c0_miss_type),
        .c0_miss_addr(c0_miss_addr),
        .c0_fill_valid(c0_fill_valid),
        .c0_fill_data(c0_fill_data),
        .c0_fill_state(c0_fill_state),
        .c1_miss_valid(c1_miss_valid),
        .c1_miss_type(c1_miss_type),
        .c1_miss_addr(c1_miss_addr),
        .c1_fill_valid(c1_fill_valid),
        .c1_fill_data(c1_fill_data),
        .c1_fill_state(c1_fill_state),
        .c0_wb_valid(c0_wb_valid),
        .c0_wb_addr(c0_wb_addr),
        .c0_wb_data(c0_wb_data),
        .c0_wb_ack(c0_wb_ack),
        .c1_wb_valid(c1_wb_valid),
        .c1_wb_addr(c1_wb_addr),
        .c1_wb_data(c1_wb_data),
        .c1_wb_ack(c1_wb_ack),
        .c0_snoop_valid(c0_snoop_valid),
        .c0_snoop_addr(c0_snoop_addr),
        .c0_snoop_invalidate(c0_snoop_invalidate),
        .c0_snoop_hit(c0_snoop_hit),
        .c0_snoop_state(c0_snoop_state),
        .c0_snoop_data(c0_snoop_data),
        .c1_snoop_valid(c1_snoop_valid),
        .c1_snoop_addr(c1_snoop_addr),
        .c1_snoop_invalidate(c1_snoop_invalidate),
        .c1_snoop_hit(c1_snoop_hit),
        .c1_snoop_state(c1_snoop_state),
        .c1_snoop_data(c1_snoop_data),
        .mem_req_valid(mem_req_valid),
        .mem_req_write(mem_req_write),
        .mem_req_addr(mem_req_addr),
        .mem_req_wdata(mem_req_wdata),
        .mem_req_ready(mem_req_ready),
        .mem_resp_valid(mem_resp_valid),
        .mem_resp_rdata(mem_resp_rdata),
        .filter_query_addr(filter_query_addr),
        .filter_hit(filter_hit),
        .filter_remove_valid(filter_remove_valid),
        .filter_remove_addr(filter_remove_addr),
        .known_absent_insert_valid(known_absent_insert_valid),
        .known_absent_insert_addr(known_absent_insert_addr),
        .filter_insert_absent(filter_insert_absent),
        .filter_insert_addr(filter_insert_addr),
        .filter_clear_all(filter_clear_all),
        .busy(busy)
    );

    // Core 0 L1 cache
    l1_cache c0 (
        .clk(clk), .rst_n(rst_n),
        .core_req_valid(c0_req_valid),
        .core_req_write(c0_req_write),
        .core_req_addr(c0_req_addr),
        .core_req_wdata(c0_req_wdata),
        .core_req_ready(c0_req_ready),
        .core_resp_valid(c0_resp_valid),
        .core_resp_rdata(c0_resp_rdata),
        .miss_req_valid(c0_miss_valid),
        .miss_req_type(c0_miss_type),
        .miss_req_addr(c0_miss_addr),
        .fill_valid(c0_fill_valid),
        .fill_data(c0_fill_data),
        .fill_state(c0_fill_state),
        .wb_req_valid(c0_wb_valid),
        .wb_req_addr(c0_wb_addr),
        .wb_req_data(c0_wb_data),
        .wb_ack(c0_wb_ack),
        .snoop_valid(c0_snoop_valid),
        .snoop_addr(c0_snoop_addr),
        .snoop_invalidate(c0_snoop_invalidate),
        .snoop_hit(c0_snoop_hit),
        .snoop_state(c0_snoop_state),
        .snoop_data(c0_snoop_data)
    );

    // Core 1 L1 cache
    l1_cache c1 (
        .clk(clk), .rst_n(rst_n),
        .core_req_valid(c1_req_valid),
        .core_req_write(c1_req_write),
        .core_req_addr(c1_req_addr),
        .core_req_wdata(c1_req_wdata),
        .core_req_ready(c1_req_ready),
        .core_resp_valid(c1_resp_valid),
        .core_resp_rdata(c1_resp_rdata),
        .miss_req_valid(c1_miss_valid),
        .miss_req_type(c1_miss_type),
        .miss_req_addr(c1_miss_addr),
        .fill_valid(c1_fill_valid),
        .fill_data(c1_fill_data),
        .fill_state(c1_fill_state),
        .wb_req_valid(c1_wb_valid),
        .wb_req_addr(c1_wb_addr),
        .wb_req_data(c1_wb_data),
        .wb_ack(c1_wb_ack),
        .snoop_valid(c1_snoop_valid),
        .snoop_addr(c1_snoop_addr),
        .snoop_invalidate(c1_snoop_invalidate),
        .snoop_hit(c1_snoop_hit),
        .snoop_state(c1_snoop_state),
        .snoop_data(c1_snoop_data)
    );

    // Simple synchronous backing memory.
    always @(posedge clk) begin
        mem_resp_valid <= 0;
        if (rst_n && mem_req_valid && mem_req_ready) begin
            if (mem_req_write) begin
                memory[mem_req_addr] <= mem_req_wdata;
            end else begin
                mem_resp_rdata <= memory[mem_req_addr];
                mem_resp_valid <= 1;
            end
        end
    end

    task check;
        input [255:0] label;
        input condition;
        begin
            if (condition !== 1'b1) begin
                $display("FAIL: %0s at time %0t", label, $time);
                errors = errors + 1;
            end else begin
                $display("PASS: %0s", label);
            end
        end
    endtask

    task access0;
        input wr;
        input [15:0] addr;
        input [31:0] data;
        integer t;
        begin
            @(negedge clk);
            c0_req_valid = 1;
            c0_req_write = wr;
            c0_req_addr = addr;
            c0_req_wdata = data;
            t = 0;
            while (!c0_req_ready && t < 100) begin
                @(negedge clk);
                t = t + 1;
            end
            if (!c0_req_ready) begin
                $display("FAIL: Core 0 request-ready timeout");
                errors = errors + 1;
                c0_req_valid = 0;
            end else begin
                @(posedge clk);
                @(negedge clk);
                c0_req_valid = 0;
                t = 0;
                while (!c0_resp_valid && t < 100) begin
                    @(negedge clk);
                    t = t + 1;
                end
                if (!c0_resp_valid) begin
                    $display("FAIL: Core 0 response timeout");
                    errors = errors + 1;
                end
            end
        end
    endtask

    task access1;
        input wr;
        input [15:0] addr;
        input [31:0] data;
        integer t;
        begin
            @(negedge clk);
            c1_req_valid = 1;
            c1_req_write = wr;
            c1_req_addr = addr;
            c1_req_wdata = data;
            t = 0;
            while (!c1_req_ready && t < 100) begin
                @(negedge clk);
                t = t + 1;
            end
            if (!c1_req_ready) begin
                $display("FAIL: Core 1 request-ready timeout");
                errors = errors + 1;
                c1_req_valid = 0;
            end else begin
                @(posedge clk);
                @(negedge clk);
                c1_req_valid = 0;
                t = 0;
                while (!c1_resp_valid && t < 100) begin
                    @(negedge clk);
                    t = t + 1;
                end
                if (!c1_resp_valid) begin
                    $display("FAIL: Core 1 response timeout");
                    errors = errors + 1;
                end
            end
        end
    endtask

    initial begin
        for (i = 0; i < 65536; i = i + 1)
            memory[i] = 32'h10000000 + i;

        repeat (3) @(negedge clk);
        rst_n = 1;

        // Insert a negative entry for an address absent from both caches.
        // No cache request or grant is pending at this point.
        @(negedge clk);
        known_absent_insert_addr = 16'h0021;
        known_absent_insert_valid = 1;
        @(negedge clk);
        known_absent_insert_valid = 0;

        // Test 0: A valid negative-filter hit must bypass the peer snoop.
        access0(0, 16'h0021, 0);
        check("Filter-hit read returns correct memory data",
              c0.data_mem[1] == 32'h10000021);
        check("Filter-hit read receives Exclusive state",
              c0.state_mem[1] == `MESI_E);
        check("Filter-hit request skipped peer snoop",
              snoop_count == 0);

        // Test 1: Core 0 reads an uncached line.
        access0(0, 16'h0010, 0);
        check("Core 0 initial read data",
              c0.data_mem[16'h0010 & 16'h0007] == 32'h10000010);
        check("Core 0 initial state is E",
              c0.state_mem[16'h0010 & 16'h0007] == `MESI_E);

        // Test 2: Core 1 reads the same line; both must become S.
        access1(0, 16'h0010, 0);
        check("Core 0 downgraded to S", c0.state_mem[0] == `MESI_S);
        check("Core 1 holds S", c1.state_mem[0] == `MESI_S);

        // Test 3: Core 1 writes the shared line.
        access1(1, 16'h0010, 32'hDEADBEEF);
        check("Core 0 invalidated after upgrade",
              c0.state_mem[0] == `MESI_I);
        check("Core 1 owns modified line",
              c1.state_mem[0] == `MESI_M);
        check("Core 1 stored new data",
              c1.data_mem[0] == 32'hDEADBEEF);

        // Test 4: Core 0 reads the modified line from Core 1.
        access0(0, 16'h0010, 0);
        check("Core 0 receives latest modified data",
              c0.data_mem[0] == 32'hDEADBEEF);
        check("Core 0 becomes Shared", c0.state_mem[0] == `MESI_S);
        check("Core 1 downgrades to Shared", c1.state_mem[0] == `MESI_S);

        // Test 5: Dirty victim writeback during replacement.
        access1(1, 16'h0010, 32'hCAFEBABE);
        access1(1, 16'h0018, 32'h12345678);
        check("Dirty victim written to backing memory",
              memory[16'h0010] == 32'hCAFEBABE);
        check("Replacement line becomes Modified",
              c1.state_mem[0] == `MESI_M);

        if (errors == 0)
            $display("PASS: all two-L1 MESI integration checks passed");
        else
            $fatal(1, "FAIL: %0d integration checks failed", errors);

        $finish;
    end

    initial begin
        #20000;
        $fatal(1, "FAIL: integration testbench global timeout");
    end

endmodule
