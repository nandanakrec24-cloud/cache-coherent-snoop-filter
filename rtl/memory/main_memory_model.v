
module main_memory_model #(
    parameter integer ADDR_WIDTH   = 16,
    parameter integer DATA_WIDTH   = 32,
    parameter integer MEM_DEPTH    = 256,
    parameter integer READ_LATENCY = 2
)(
    input wire clk,
    input wire rst_n,

    // Memory request interface
    input wire mem_req_valid,
    input wire mem_req_write,
    input wire [ADDR_WIDTH-1:0] mem_req_addr,
    input wire [DATA_WIDTH-1:0] mem_req_wdata,
    output wire mem_req_ready,

    // Memory response interface
    output reg mem_resp_valid,
    output reg [DATA_WIDTH-1:0] mem_resp_rdata
);

    // Backing memory storage
    reg [DATA_WIDTH-1:0] memory [0:MEM_DEPTH-1];

    // Internal control registers
    reg busy;
    reg [DATA_WIDTH-1:0] saved_rdata;
    reg [31:0] latency_count;

    integer i;

    // Address mapping
    wire [31:0] memory_index;

    assign memory_index = mem_req_addr % MEM_DEPTH;

    // Ensure minimum read latency is one clock cycle
    localparam integer EFFECTIVE_READ_LATENCY =
        (READ_LATENCY < 1) ? 1 : READ_LATENCY;

    // Memory is ready when no read response is pending
    assign mem_req_ready = rst_n && !busy;

    // Initialize memory for simulation
    // Memory contents are not cleared during reset
    initial begin
        for (i = 0; i < MEM_DEPTH; i = i + 1)
            memory[i] = {DATA_WIDTH{1'b0}};
    end

    // Memory request and response logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 1'b0;
            saved_rdata <= {DATA_WIDTH{1'b0}};
            latency_count <= 32'd0;
            mem_resp_valid <= 1'b0;
            mem_resp_rdata <= {DATA_WIDTH{1'b0}};
        end
        else begin
            // Default: response is a one-cycle pulse
            mem_resp_valid <= 1'b0;

            // Accept a new memory request
            if (mem_req_valid && mem_req_ready) begin

                if (mem_req_write) begin
                    // WRITE operation
                    memory[memory_index] <= mem_req_wdata;
                end
                else begin
                    // READ operation
                    saved_rdata <= memory[memory_index];
                    latency_count <= EFFECTIVE_READ_LATENCY;
                    busy <= 1'b1;
                end
            end

            // Generate delayed READ response
            else if (busy) begin

                if (latency_count > 1) begin
                    latency_count <= latency_count - 1'b1;
                end
                else begin
                    mem_resp_rdata <= saved_rdata;
                    mem_resp_valid <= 1'b1;
                    busy <= 1'b0;
                end

            end
        end
    end

endmodule


