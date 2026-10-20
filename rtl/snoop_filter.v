// Exclusive negative snoop filter, Verilog-2001
// A stored address is known absent from BOTH private caches.
// Hit => remote snoop may be skipped. Miss => remote snoop is required.
// Insert only when both caches are absent AND no fill/ownership grant for
// that address is pending (typically after the last cached copy is evicted).
// Remove before either cache acquires/installs the address.
// remove_addr_valid has priority over insert_absent; do not assert both together.
module snoop_filter #(
    parameter ADDR_WIDTH = 16,
    parameter FILTER_ENTRIES = 4
) (
    input  wire                  clk,
    input  wire                  rst_n,  // active-low asynchronous reset
    input  wire [ADDR_WIDTH-1:0] query_addr,
    output reg                   filter_hit,
    output wire                  snoop_required,
    input  wire                  insert_absent,
    input  wire [ADDR_WIDTH-1:0] insert_addr,
    input  wire                  remove_addr_valid,
    input  wire [ADDR_WIDTH-1:0] remove_addr,
    input  wire                  clear_all
);
    assign snoop_required = ~filter_hit;

    generate
        if (FILTER_ENTRIES == 0) begin : gen_bypass
            // No storage: filtering disabled, every lookup requires a snoop.
            always @* filter_hit = 1'b0;
        end else begin : gen_filter
            reg [ADDR_WIDTH-1:0] addr_mem [0:FILTER_ENTRIES-1];
            reg valid_mem [0:FILTER_ENTRIES-1];
            integer replace_ptr;
            integer i_lookup;
            integer i_seq;
            integer duplicate_found;
            integer free_found;
            integer free_index;

            // Fully associative combinational lookup.
            always @* begin
                filter_hit = 1'b0;
                for (i_lookup = 0; i_lookup < FILTER_ENTRIES; i_lookup = i_lookup + 1)
                    if (valid_mem[i_lookup] && addr_mem[i_lookup] == query_addr)
                        filter_hit = 1'b1;
            end

            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    replace_ptr <= 0;
                    for (i_seq = 0; i_seq < FILTER_ENTRIES; i_seq = i_seq + 1) begin
                        valid_mem[i_seq] <= 1'b0;
                        addr_mem[i_seq] <= {ADDR_WIDTH{1'b0}};
                    end
                end else if (clear_all) begin
                    replace_ptr <= 0;
                    for (i_seq = 0; i_seq < FILTER_ENTRIES; i_seq = i_seq + 1) begin
                        valid_mem[i_seq] <= 1'b0;
                        addr_mem[i_seq] <= {ADDR_WIDTH{1'b0}};
                    end
                end else if (remove_addr_valid) begin
                    // Remove all matching copies; normally there is only one.
                    for (i_seq = 0; i_seq < FILTER_ENTRIES; i_seq = i_seq + 1)
                        if (valid_mem[i_seq] && addr_mem[i_seq] == remove_addr)
                            valid_mem[i_seq] <= 1'b0;
                end else if (insert_absent) begin
                    duplicate_found = 0;
                    free_found = 0;
                    free_index = 0;

                    for (i_seq = 0; i_seq < FILTER_ENTRIES; i_seq = i_seq + 1) begin
                        if (valid_mem[i_seq] && addr_mem[i_seq] == insert_addr)
                            duplicate_found = 1;
                        if (!valid_mem[i_seq] && free_found == 0) begin
                            free_found = 1;
                            free_index = i_seq;
                        end
                    end

                    if (duplicate_found == 0) begin
                        if (free_found != 0) begin
                            // Fill an unused slot before replacing negative knowledge.
                            addr_mem[free_index] <= insert_addr;
                            valid_mem[free_index] <= 1'b1;
                        end else begin
                            // Full table: round-robin replacement. Safe because an
                            // evicted entry only loses an opportunity to skip a snoop.
                            addr_mem[replace_ptr] <= insert_addr;
                            valid_mem[replace_ptr] <= 1'b1;
                            if (replace_ptr == FILTER_ENTRIES-1)
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