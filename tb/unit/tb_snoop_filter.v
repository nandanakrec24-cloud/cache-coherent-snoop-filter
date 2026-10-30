`timescale 1ns/1ps
module tb_snoop_filter;
    parameter FILTER_ENTRIES = 4;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg [15:0] query_addr = 16'h0000;
    wire filter_hit;
    wire snoop_required;
    reg insert_absent = 1'b0;
    reg [15:0] insert_addr = 16'h0000;
    reg remove_addr_valid = 1'b0;
    reg [15:0] remove_addr = 16'h0000;
    reg clear_all = 1'b0;

    integer errors = 0;
    integer k;

    snoop_filter #(
        .ADDR_WIDTH(16),
        .FILTER_ENTRIES(FILTER_ENTRIES)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .query_addr(query_addr),
        .filter_hit(filter_hit),
        .snoop_required(snoop_required),
        .insert_absent(insert_absent),
        .insert_addr(insert_addr),
        .remove_addr_valid(remove_addr_valid),
        .remove_addr(remove_addr),
        .clear_all(clear_all)
    );

    always #5 clk = ~clk;

    task check_lookup;
        input [15:0] addr;
        input expected_hit;
        begin
            query_addr = addr;
            #1;
            if (filter_hit !== expected_hit) begin
                $display("FAIL lookup addr=%h expected_hit=%b got=%b",
                         addr, expected_hit, filter_hit);
                errors = errors + 1;
            end
            if (snoop_required !== ~expected_hit) begin
                $display("FAIL snoop_required addr=%h expected=%b got=%b",
                         addr, ~expected_hit, snoop_required);
                errors = errors + 1;
            end
        end
    endtask

    task do_insert;
        input [15:0] addr;
        begin
            @(negedge clk);
            insert_addr = addr;
            insert_absent = 1'b1;
            @(negedge clk);
            insert_absent = 1'b0;
        end
    endtask

    task do_remove;
        input [15:0] addr;
        begin
            @(negedge clk);
            remove_addr = addr;
            remove_addr_valid = 1'b1;
            @(negedge clk);
            remove_addr_valid = 1'b0;
        end
    endtask

    task do_clear;
        begin
            @(negedge clk);
            clear_all = 1'b1;
            @(negedge clk);
            clear_all = 1'b0;
        end
    endtask

    initial begin
        $dumpfile("/tmp/snoop_filter.vcd");
        $dumpvars(0, tb_snoop_filter);
        $display("Starting snoop_filter tests; FILTER_ENTRIES=%0d", FILTER_ENTRIES);

        // Hold reset for two falling edges, then release it.
        repeat (2) @(negedge clk);
        rst_n = 1'b1;
        #1;

        check_lookup(16'h0010, 1'b0);

        if (FILTER_ENTRIES == 0) begin
            do_insert(16'h0010);
            check_lookup(16'h0010, 1'b0);
            do_remove(16'h0010);
            check_lookup(16'h0010, 1'b0);
            do_clear();
            check_lookup(16'h0010, 1'b0);
        end else begin
            // Insert and query.
            do_insert(16'h0010);
            check_lookup(16'h0010, 1'b1);
            check_lookup(16'h0011, 1'b0);

            // Duplicate insertion should not harm lookup behavior.
            do_insert(16'h0010);
            check_lookup(16'h0010, 1'b1);

            // Remove present and absent addresses.
            do_remove(16'h0010);
            check_lookup(16'h0010, 1'b0);
            do_remove(16'h00FF);
            check_lookup(16'h0010, 1'b0);

            // Clear any old entries, then test filling and replacement.
            do_clear();
            for (k = 0; k < FILTER_ENTRIES; k = k + 1)
                do_insert(16'h0100 + k);

            for (k = 0; k < FILTER_ENTRIES; k = k + 1)
                check_lookup(16'h0100 + k, 1'b1);

            // Table is full. New address triggers round-robin replacement.
            // After clear, replacement pointer resets to slot zero.
            do_insert(16'h0200);
            check_lookup(16'h0200, 1'b1);
            check_lookup(16'h0100, 1'b0);
            for (k = 1; k < FILTER_ENTRIES; k = k + 1)
                check_lookup(16'h0100 + k, 1'b1);

            // Clear invalidates every entry.
            do_clear();
            check_lookup(16'h0200, 1'b0);
            for (k = 1; k < FILTER_ENTRIES; k = k + 1)
                check_lookup(16'h0100 + k, 1'b0);
        end

        if (errors == 0) begin
            $display("PASS: all snoop_filter checks passed (FILTER_ENTRIES=%0d)",
                     FILTER_ENTRIES);
            $finish;
        end else begin
            $display("FAIL: %0d check(s) failed", errors);
            $fatal(1);
        end
    end
endmodule
