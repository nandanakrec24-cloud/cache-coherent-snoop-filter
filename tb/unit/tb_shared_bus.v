
`timescale 1ns/1ps

module tb_shared_bus;

    reg clk = 1'b0;
    reg rst_n = 1'b0;

    // Controller-side request signals
    reg ctrl_req_valid = 1'b0;
    reg ctrl_req_write = 1'b0;
    reg [15:0] ctrl_req_addr = 16'h0000;
    reg [31:0] ctrl_req_wdata = 32'h00000000;
    wire ctrl_req_ready;

    // Memory-side request signals
    wire mem_req_valid;
    wire mem_req_write;
    wire [15:0] mem_req_addr;
    wire [31:0] mem_req_wdata;
    reg mem_req_ready = 1'b0;

    // Memory-side response signals
    reg mem_resp_valid = 1'b0;
    reg [31:0] mem_resp_rdata = 32'h00000000;

    // Controller-side response signals
    wire ctrl_resp_valid;
    wire [31:0] ctrl_resp_rdata;

    integer errors = 0;
    integer k;

    // DUT instantiation
    shared_bus dut (
        .clk(clk),
        .rst_n(rst_n),

        .ctrl_req_valid(ctrl_req_valid),
        .ctrl_req_write(ctrl_req_write),
        .ctrl_req_addr(ctrl_req_addr),
        .ctrl_req_wdata(ctrl_req_wdata),
        .ctrl_req_ready(ctrl_req_ready),

        .mem_req_valid(mem_req_valid),
        .mem_req_write(mem_req_write),
        .mem_req_addr(mem_req_addr),
        .mem_req_wdata(mem_req_wdata),
        .mem_req_ready(mem_req_ready),

        .mem_resp_valid(mem_resp_valid),
        .mem_resp_rdata(mem_resp_rdata),

        .ctrl_resp_valid(ctrl_resp_valid),
        .ctrl_resp_rdata(ctrl_resp_rdata)
    );

    // Clock generation
    always #5 clk = ~clk;

    // Check request forwarding and handshake
    task check_request;
        input expected_valid;
        input expected_ready;
        input expected_write;
        input [15:0] expected_addr;
        input [31:0] expected_wdata;

        begin
            #1;

            if (mem_req_valid !== expected_valid) begin
                $display("FAIL mem_req_valid expected=%b got=%b",
                         expected_valid, mem_req_valid);
                errors = errors + 1;
            end

            if (ctrl_req_ready !== expected_ready) begin
                $display("FAIL ctrl_req_ready expected=%b got=%b",
                         expected_ready, ctrl_req_ready);
                errors = errors + 1;
            end

            if (expected_valid) begin
                if (mem_req_write !== expected_write ||
                    mem_req_addr !== expected_addr ||
                    mem_req_wdata !== expected_wdata) begin

                    $display("FAIL request forwarding mismatch");
                    errors = errors + 1;
                end
            end
        end
    endtask

    // Check controller response
    task check_response;
        input expected_valid;
        input [31:0] expected_data;

        begin
            #1;

            if (ctrl_resp_valid !== expected_valid) begin
                $display("FAIL ctrl_resp_valid expected=%b got=%b",
                         expected_valid, ctrl_resp_valid);
                errors = errors + 1;
            end

            if (expected_valid &&
                ctrl_resp_rdata !== expected_data) begin

                $display("FAIL response data expected=%h got=%h",
                         expected_data, ctrl_resp_rdata);
                errors = errors + 1;
            end
        end
    endtask

    initial begin

        $dumpfile("build/shared_bus.vcd");
        $dumpvars(0, tb_shared_bus);

        $display("Starting shared_bus tests");

        // --------------------------------
        // TEST 1: Reset and IDLE state
        // --------------------------------

        repeat (2) @(negedge clk);
        rst_n = 1'b1;

        check_request(1'b0, 1'b0, 1'b0,
                      16'h0000, 32'h00000000);

        check_response(1'b0, 32'h00000000);

        $display("TEST 1: Reset and IDLE check completed");

        // --------------------------------
        // TEST 2: WRITE with backpressure
        // --------------------------------

        @(negedge clk);

        ctrl_req_valid = 1'b1;
        ctrl_req_write = 1'b1;
        ctrl_req_addr = 16'h0010;
        ctrl_req_wdata = 32'hAABBCCDD;
        mem_req_ready = 1'b0;

        // Hold request for multiple cycles
        repeat (3) begin
            check_request(1'b1, 1'b0, 1'b1,
                          16'h0010, 32'hAABBCCDD);

            @(negedge clk);
        end

        // Memory becomes ready
        mem_req_ready = 1'b1;

        check_request(1'b1, 1'b1, 1'b1,
                      16'h0010, 32'hAABBCCDD);

        // WRITE acceptance
        @(posedge clk);
        @(negedge clk);

        ctrl_req_valid = 1'b0;
        mem_req_ready = 1'b0;

        check_response(1'b0, 32'h00000000);

        $display("TEST 2: WRITE and backpressure completed");

        // --------------------------------
        // TEST 3: READ request acceptance
        // --------------------------------

        @(negedge clk);

        ctrl_req_valid = 1'b1;
        ctrl_req_write = 1'b0;
        ctrl_req_addr = 16'h0020;
        ctrl_req_wdata = 32'h00000000;
        mem_req_ready = 1'b1;

        check_request(1'b1, 1'b1, 1'b0,
                      16'h0020, 32'h00000000);

        // READ acceptance
        @(posedge clk);
        @(negedge clk);

        ctrl_req_valid = 1'b0;
        mem_req_ready = 1'b0;

        check_response(1'b0, 32'h00000000);

        $display("TEST 3: READ request acceptance completed");

        // --------------------------------
        // TEST 4: Block new request while
        // previous READ response is pending
        // --------------------------------

        ctrl_req_valid = 1'b1;
        ctrl_req_write = 1'b1;
        ctrl_req_addr = 16'h0030;
        ctrl_req_wdata = 32'h12345678;
        mem_req_ready = 1'b1;

        repeat (3) begin
            check_request(1'b0, 1'b0, 1'b1,
                          16'h0030, 32'h12345678);

            @(negedge clk);
        end

        $display("TEST 4: Pending READ blocks new request");

        // --------------------------------
        // TEST 5: Forward READ response
        // --------------------------------

        mem_resp_rdata = 32'hDEADBEEF;
        mem_resp_valid = 1'b1;

        check_response(1'b1, 32'hDEADBEEF);

        // Response accepted at rising edge
        @(posedge clk);
        @(negedge clk);

        mem_resp_valid = 1'b0;
        mem_req_ready = 1'b0;
        ctrl_req_valid = 1'b0;

        check_response(1'b0, 32'h00000000);

        $display("TEST 5: READ response forwarding completed");

        // --------------------------------
        // TEST 6: Accept next request after
        // previous READ response completes
        // --------------------------------

        @(negedge clk);

        ctrl_req_valid = 1'b1;
        ctrl_req_write = 1'b1;
        ctrl_req_addr = 16'h0040;
        ctrl_req_wdata = 32'hCAFEBABE;
        mem_req_ready = 1'b1;

        check_request(1'b1, 1'b1, 1'b1,
                      16'h0040, 32'hCAFEBABE);

        @(posedge clk);
        @(negedge clk);

        ctrl_req_valid = 1'b0;
        mem_req_ready = 1'b0;

        $display("TEST 6: Next request acceptance completed");

        // --------------------------------
        // FINAL RESULT
        // --------------------------------

        if (errors == 0) begin
            $display("--------------------------------");
            $display("PASS: All shared_bus checks passed");
            $display("--------------------------------");
            $finish;
        end
        else begin
            $display("--------------------------------");
            $display("FAIL: %0d check(s) failed", errors);
            $display("--------------------------------");
            $fatal(1);
        end

    end

endmodule


