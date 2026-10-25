`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// Exclusive negative snoop filter
//
// Meaning of a valid entry:
//   The address is known to be absent from BOTH private L1 caches.
//
// Therefore:
//   filter_hit = 1  -> remote snoop may be skipped (if system update ordering
//                      guarantees the invariant above).
//   filter_hit = 0  -> normal snoop path is required.
//
// Important integration contract:
//   * Remove an address before any cache can acquire/install it.
//   * Insert only after both caches are known absent and no fill/ownership
//     grant for that address is pending.
//   * A filter eviction only loses negative knowledge; it must never suppress
//     a snoop incorrectly.
// -----------------------------------------------------------------------------
module snoop_filter #(
    parameter ADDR_WIDTH = 16,
    parameter FILTER_ENTRIES = 4
) (
    input  wire                  clk,
    input  wire                  rst_n,

    input  wire [ADDR_WIDTH-1:0] query_addr,
    output wire                  filter_hit,
    output wire                  snoop_required,

    input  wire                  insert_absent,
    input  wire [ADDR_WIDTH-1:0] insert_addr,

    input  wire                  remove_addr_valid,
    input  wire [ADDR_WIDTH-1:0] remove_addr,

    input  wire                  clear_all
);

generate
    // Zero-entry mode is a true bypass: every lookup misses.
    if (FILTER_ENTRIES == 0) begin : g_bypass
        assign filter_hit      = 1'b0;
        assign snoop_required  = 1'b1;
    end else begin : g_filter
        reg [ADDR_WIDTH-1:0] addr_mem [0:FILTER_ENTRIES-1];
        reg                  valid_mem [0:FILTER_ENTRIES-1];

        integer lookup_i;
        integer seq_i;
        integer duplicate_found;
        integer free_found;
        integer free_index;
        integer replace_ptr;
        reg     hit_comb;

        // Combinational fully-associative lookup.
        always @* begin
            hit_comb = 1'b0;
            for (lookup_i = 0; lookup_i < FILTER_ENTRIES;
                 lookup_i = lookup_i + 1) begin
                if (valid_mem[lookup_i] &&
                    (addr_mem[lookup_i] == query_addr)) begin
                    hit_comb = 1'b1;
                end
            end
        end

        assign filter_hit     = hit_comb;
        assign snoop_required = ~filter_hit;

        // Update priority:
        // asynchronous reset > clear_all > remove > insert > hold.
        // Removal wins over insertion if both are asserted in one cycle.
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                replace_ptr <= 0;
                for (seq_i = 0; seq_i < FILTER_ENTRIES; seq_i = seq_i + 1) begin
                    valid_mem[seq_i] <= 1'b0;
                    addr_mem[seq_i]  <= {ADDR_WIDTH{1'b0}};
                end
            end else if (clear_all) begin
                replace_ptr <= 0;
                for (seq_i = 0; seq_i < FILTER_ENTRIES; seq_i = seq_i + 1)
                    valid_mem[seq_i] <= 1'b0;
            end else if (remove_addr_valid) begin
                for (seq_i = 0; seq_i < FILTER_ENTRIES; seq_i = seq_i + 1) begin
                    if (valid_mem[seq_i] && (addr_mem[seq_i] == remove_addr))
                        valid_mem[seq_i] <= 1'b0;
                end
            end else if (insert_absent) begin
                // First check for duplicates and the first invalid slot.
                // These are temporary procedural variables, not state.
                duplicate_found = 0;
                free_found      = 0;
                free_index      = 0;

                for (seq_i = 0; seq_i < FILTER_ENTRIES; seq_i = seq_i + 1) begin
                    if (valid_mem[seq_i] && (addr_mem[seq_i] == insert_addr))
                        duplicate_found = 1;

                    if (!valid_mem[seq_i] && !free_found) begin
                        free_found = 1;
                        free_index = seq_i;
                    end
                end

                // Ignore duplicate inserts. Use a free slot when available.
                // When full, replace one entry in round-robin order.
                if (!duplicate_found) begin
                    if (free_found) begin
                        addr_mem[free_index] <= insert_addr;
                        valid_mem[free_index] <= 1'b1;
                    end else begin
                        addr_mem[replace_ptr] <= insert_addr;
                        valid_mem[replace_ptr] <= 1'b1;

                        if (replace_ptr == FILTER_ENTRIES - 1)
                            replace_ptr <= 0;
                        else
                            replace_ptr <= replace_ptr + 1;
                    end
                end
            end
        end
    end
endgenerate

endmodule
