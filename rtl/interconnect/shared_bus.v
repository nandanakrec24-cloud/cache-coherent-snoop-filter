
module shared_bus (
    input wire clk,
    input wire rst_n,

    // Controller-side request interface
    input wire ctrl_req_valid,
    input wire ctrl_req_write,
    input wire [15:0] ctrl_req_addr,
    input wire [31:0] ctrl_req_wdata,
    output wire ctrl_req_ready,

    // Memory-side request interface
    output wire mem_req_valid,
    output wire mem_req_write,
    output wire [15:0] mem_req_addr,
    output wire [31:0] mem_req_wdata,
    input wire mem_req_ready,

    // Memory-side response interface
    input wire mem_resp_valid,
    input wire [31:0] mem_resp_rdata,

    // Controller-side response interface
    output wire ctrl_resp_valid,
    output wire [31:0] ctrl_resp_rdata
);

    // FSM state encoding
    localparam IDLE      = 1'b0;
    localparam WAIT_RESP = 1'b1;

    reg state;
    reg next_state;

    // State register
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= next_state;
    end

    // Next-state logic
    always @(*) begin
        next_state = state;

        case (state)

            IDLE: begin
                if (ctrl_req_valid && mem_req_ready) begin
                    if (!ctrl_req_write)
                        next_state = WAIT_RESP;
                    else
                        next_state = IDLE;
                end
            end

            WAIT_RESP: begin
                if (mem_resp_valid)
                    next_state = IDLE;
            end

            default: begin
                next_state = IDLE;
            end

        endcase
    end

    // Controller and memory request handshake
    assign mem_req_valid = (state == IDLE) && ctrl_req_valid;

    assign ctrl_req_ready =
        (state == IDLE) && ctrl_req_valid && mem_req_ready;

    // Forward request signals to memory
    assign mem_req_write = ctrl_req_write;
    assign mem_req_addr  = ctrl_req_addr;
    assign mem_req_wdata = ctrl_req_wdata;

    // Forward read response to controller
    assign ctrl_resp_valid =
        (state == WAIT_RESP) && mem_resp_valid;

    assign ctrl_resp_rdata = mem_resp_rdata;

endmodule
