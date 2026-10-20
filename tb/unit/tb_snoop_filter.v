`timescale 1ns/1ps
module tb_snoop_filter #(parameter FILTER_ENTRIES = 4);
    reg clk, rst_n;
    reg [15:0] query_addr;
    wire filter_hit, snoop_required;
    reg insert_absent;
    reg [15:0] insert_addr;
    reg remove_addr_valid;
    reg [15:0] remove_addr;
    reg clear_all;
    integer errors;

    // Set FILTER_ENTRIES to 0 to test bypass behavior.
    snoop_filter #(.ADDR_WIDTH(16), .FILTER_ENTRIES(FILTER_ENTRIES)) dut (
        .clk(clk), .rst_n(rst_n),
        .query_addr(query_addr), .filter_hit(filter_hit),
        .snoop_required(snoop_required),
        .insert_absent(insert_absent), .insert_addr(insert_addr),
        .remove_addr_valid(remove_addr_valid), .remove_addr(remove_addr),
        .clear_all(clear_all)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task check_hit;
        input expected;
        input [8*70-1:0] label_text;
        begin
            #1;
            if (filter_hit !== expected) begin
                $display("FAIL: %0s addr=%h expected=%b actual=%b",
                         label_text, query_addr, expected, filter_hit);
                errors = errors + 1;
            end else begin
                $display("PASS: %0s addr=%h hit=%b snoop_required=%b",
                         label_text, query_addr, filter_hit, snoop_required);
            end
        end
    endtask

    task insert_address;
        input [15:0] address;
        begin
            @(negedge clk); insert_addr = address; insert_absent = 1'b1;
            @(negedge clk); insert_absent = 1'b0;
        end
    endtask

    task remove_address;
        input [15:0] address;
        begin
            @(negedge clk); remove_addr = address; remove_addr_valid = 1'b1;
            @(negedge clk); remove_addr_valid = 1'b0;
        end
    endtask

    initial begin
        errors = 0;
        rst_n = 0;
        query_addr = 0;
        insert_absent = 0; insert_addr = 0;
        remove_addr_valid = 0; remove_addr = 0;
        clear_all = 0;

        repeat (2) @(negedge clk);
        rst_n = 1;

        if (FILTER_ENTRIES == 0) begin
            query_addr = 16'h1234;
            check_hit(0, "bypass starts with filter miss");
            insert_address(16'h1234);
            query_addr = 16'h1234;
            check_hit(0, "bypass ignores insert and always requires snoop");
            remove_address(16'h1234);
            check_hit(0, "bypass remains disabled after remove");
        end else begin
            query_addr = 16'h1234;
            check_hit(0, "empty table misses");

            insert_address(16'h1234);
            query_addr = 16'h1234;
            check_hit(1, "inserted address hits");

            query_addr = 16'h5678;
            check_hit(0, "unrelated address misses");

            remove_address(16'h1234);
            query_addr = 16'h1234;
            check_hit(0, "removed address misses");

            insert_address(16'h0010);
            insert_address(16'h0020);
            insert_address(16'h0030);
            insert_address(16'h0040);
            query_addr = 16'h0010;
            check_hit(1, "address exists before replacement");

            // With four entries filled, the first full-table insert replaces slot 0.
            insert_address(16'h0050);
            query_addr = 16'h0010;
            check_hit(0, "round-robin replacement evicts slot zero");
            query_addr = 16'h0050;
            check_hit(1, "replacement address hits");

            @(negedge clk); clear_all = 1;
            @(negedge clk); clear_all = 0;
            query_addr = 16'h0050;
            check_hit(0, "clear_all empties table");
        end

        if (errors == 0) $display("\nALL SNOOP-FILTER TESTS PASSED");
        else $display("\nTESTS FAILED: %0d error(s)", errors);
        $finish;
    end
endmodule
