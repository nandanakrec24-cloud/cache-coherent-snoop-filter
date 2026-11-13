
`timescale 1ns/1ps

module tb_main_memory_model;

    reg clk = 1'b0;
    reg rst_n = 1'b0;

    // Memory request interface
    reg mem_req_valid = 1'b0;
    reg mem_req_write = 1'b0;
    reg [15:0] mem_req_addr = 16'h0000;
    reg [31:0] mem_req_wdata = 32'h00000000;
    wire mem_req_ready;

    // Memory response interface
    wire mem_resp_valid;
    wire [31:0] mem_resp_rdata;

    integer errors = 0;
    integer wait_cycles;
    integer found;

    // DUT instantiation
    main_memory_model #(
        .ADDR_WIDTH(16),
        .DATA_WIDTH(32),
        .MEM_DEPTH(256),
        .READ_LATENCY(2)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),

        .mem_req_valid(mem_req_valid),
        .mem_req_write(mem_req_write),
        .mem_req_addr(mem_req_addr),
        .mem_req_wdata(mem_req_wdata),
        .mem_req_ready(mem_req_ready),

        .mem_resp_valid(mem_resp_valid),
        .mem_resp_rdata(mem_resp_rdata)
    );

    // Clock generation
    always #5 clk = ~clk;

    // WRITE operation
    task memory_write;
        input [15:0] address;
        input [31:0] data;

        begin
            @(negedge clk);

            mem_req_valid = 1'b1;
            mem_req_write = 1'b1;
            mem_req_addr = address;
            mem_req_wdata = data;

            #1;

            if (mem_req_ready !== 1'b1) begin
                $display("FAIL: Memory not ready for WRITE");
                errors = errors + 1;
            end

            @(posedge clk);
            #1;

            if (mem_resp_valid !== 1'b0) begin
                $display("FAIL: Unexpected response after WRITE");
                errors = errors + 1;
            end

            @(negedge clk);
            mem_req_valid = 1'b0;
            mem_req_write = 1'b0;
        end
    endtask

    // READ operation
    task memory_read;
        input [15:0] address;
        input [31:0] expected_data;

        begin
            @(negedge clk);

            mem_req_valid = 1'b1;
            mem_req_write = 1'b0;
            mem_req_addr = address;
            mem_req_wdata = 32'h00000000;

            #1;

            if (mem_req_ready !== 1'b1) begin
                $display("FAIL: Memory not ready for READ");
                errors = errors + 1;
            end

            // Accept READ request
            @(posedge clk);
            #1;

            mem_req_valid = 1'b0;

            if (mem_req_ready !== 1'b0) begin
                $display("FAIL: Memory should be busy after READ");
                errors = errors + 1;
            end

            // Wait for delayed READ response
            found = 0;

            for (wait_cycles = 0;
                 wait_cycles < 10;
                 wait_cycles = wait_cycles + 1) begin

                @(posedge clk);
                #1;

                if (mem_resp_valid === 1'b1) begin

                    found = 1;

                    if (mem_resp_rdata !== expected_data) begin
                        $display("FAIL: READ address=%h expected=%h got=%h",
                                 address, expected_data, mem_resp_rdata);
                        errors = errors + 1;
                    end
                    else begin
                        $display("PASS: READ address=%h data=%h",
                                 address, mem_resp_rdata);
                    end

                    wait_cycles = 10;
                end
            end

            if (found == 0) begin
                $display("FAIL: READ response timeout at address=%h",
                         address);
                errors = errors + 1;
            end

            // Check response is a one-cycle pulse
            @(posedge clk);
            #1;

            if (mem_resp_valid !== 1'b0) begin
                $display("FAIL: READ response was not a one-cycle pulse");
                errors = errors + 1;
            end

        end
    endtask

    initial begin

        $dumpfile("build/main_memory_model.vcd");
        $dumpvars(0, tb_main_memory_model);

        $display("-----------------------------------");
        $display("Starting main_memory_model tests");
        $display("-----------------------------------");

        // TEST 1: Reset
        repeat (2) @(negedge clk);
        rst_n = 1'b1;

        #1;

        if (mem_req_ready !== 1'b1) begin
            $display("FAIL: Memory not ready after reset");
            errors = errors + 1;
        end
        else begin
            $display("PASS: Reset and IDLE check");
        end

        // TEST 2: Read initialized memory location
        memory_read(16'h0010, 32'h00000000);

        // TEST 3: Write data into memory
        memory_write(16'h0010, 32'hAABBCCDD);
        $display("PASS: WRITE address=0010 data=AABBCCDD");

        // TEST 4: Read back written data
        memory_read(16'h0010, 32'hAABBCCDD);

        // TEST 5: Write and read another location
        memory_write(16'h0020, 32'h12345678);
        $display("PASS: WRITE address=0020 data=12345678");

        memory_read(16'h0020, 32'h12345678);

        // TEST 6: Reset should not clear memory contents
        @(negedge clk);
        rst_n = 1'b0;

        @(posedge clk);
        #1;

        if (mem_req_ready !== 1'b0) begin
            $display("FAIL: Memory ready during reset");
            errors = errors + 1;
        end

        @(negedge clk);
        rst_n = 1'b1;

        #1;

        memory_read(16'h0010, 32'hAABBCCDD);

        // FINAL RESULT
        $display("-----------------------------------");

        if (errors == 0) begin
            $display("PASS: All memory model tests passed");
            $finish;
        end
        else begin
            $display("FAIL: %0d test(s) failed", errors);
            $fatal(1);
        end

    end

endmodule
