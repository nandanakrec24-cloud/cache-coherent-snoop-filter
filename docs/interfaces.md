# Module Interface Contract

Update this document before making cross-module port changes.

## `snoop_filter`

| Signal | Direction | Meaning |
|---|---|---|
| `clk` | input | rising-edge clock |
| `rst_n` | input | active-low asynchronous reset |
| `query_addr` | input | address being checked |
| `filter_hit` | output | address is recorded as absent from both caches |
| `snoop_required` | output | inverse of `filter_hit` |
| `insert_absent` | input | insert `insert_addr` as known absent |
| `insert_addr` | input | address for insertion |
| `remove_addr_valid` | input | remove `remove_addr` on this cycle |
| `remove_addr` | input | address to invalidate from filter |
| `clear_all` | input | invalidate all filter entries |

If remove and insert are asserted together, remove has priority. `clear_all` has priority over both. The filter's query is combinational; updates occur on the rising clock edge.

## Planned interfaces — not yet frozen

- `l1_cache`: core request, response, line/tag/state status, snoop request/response.
- `mesi_controller`: request arbitration, snoop decisions, ownership transfers, filter update events.
- `shared_bus`: serialized command/address/data path.
- `main_memory_model`: request/ready/response interface.
- `ccms_top`: connects two caches, controller, bus, memory, and filter.

Do not code against these planned interfaces until the team freezes their port lists.

## `shared_bus` — proposed interface

| Signal | Direction | Meaning |
|---|---|---|
| `clk` | input | Rising-edge clock. |
| `rst_n` | input | Active-low asynchronous reset. |
| `core0_req_valid` | input | Core 0 requests a shared-bus transaction. |
| `core0_req_addr` | input | Address requested by Core 0. |
| `core0_req_cmd` | input | Command requested by Core 0; encoding to be agreed with the team. |
| `core0_req_wdata` | input | Write data supplied by Core 0. |
| `core0_req_ready` | output | Indicates that Core 0's request can be accepted. |
| `core1_req_valid` | input | Core 1 requests a shared-bus transaction. |
| `core1_req_addr` | input | Address requested by Core 1. |
| `core1_req_cmd` | input | Command requested by Core 1; encoding to be agreed with the team. |
| `core1_req_wdata` | input | Write data supplied by Core 1. |
| `core1_req_ready` | output | Indicates that Core 1's request can be accepted. |
| `mem_req_valid` | output | A memory transaction is being presented to the memory model. |
| `mem_req_addr` | output | Address of the selected transaction. |
| `mem_req_cmd` | output | Command of the selected transaction. |
| `mem_req_wdata` | output | Write data for the selected transaction. |
| `mem_req_ready` | input | Memory model indicates it can accept the transaction. |
| `mem_resp_valid` | input | Memory model indicates that a response is available. |
| `mem_resp_rdata` | input | Read data returned by the memory model. |
| `core0_resp_valid` | output | A response for Core 0 is available. |
| `core0_resp_rdata` | output | Read data returned to Core 0. |
| `core1_resp_valid` | output | A response for Core 1 is available. |
| `core1_resp_rdata` | output | Read data returned to Core 1. |

**Behaviour notes (proposed; pending team review):**

- The bus serializes transactions: at most one request is forwarded to the memory model at a time.
- If both cores request simultaneously, arbitration selects one requester. The arbitration policy (for example, fixed priority or round-robin) must be agreed with the team.
- A request is accepted only when the corresponding valid/ready handshake succeeds.
- The selected request's address, command, and write data must remain consistent while the transaction is waiting for acceptance.
- The response must be routed back to the core that initiated the accepted transaction. Only one outstanding transaction is assumed in this initial proposal.
- Address width, data width, command encodings, response timing, and exact handshake rules must be agreed with the L1 cache, MESI controller, and memory-model owners before the interface is frozen.


## `main_memory_model` — proposed interface

| Signal | Direction | Meaning |
|---|---|---|
| `clk` | input | Rising-edge clock. |
| `rst_n` | input | Active-low asynchronous reset. |
| `mem_req_valid` | input | Indicates that the bus is presenting a memory request. |
| `mem_req_addr` | input | Address for the memory operation. |
| `mem_req_cmd` | input | Command specifying the operation; encoding to be agreed with the team. |
| `mem_req_wdata` | input | Data to be written for a write operation. |
| `mem_req_ready` | output | Indicates that the memory model can accept a request. |
| `mem_resp_valid` | output | Indicates that a response is available. |
| `mem_resp_rdata` | output | Read data returned for a read operation. |

**Behaviour notes (proposed; pending team review):**

- The memory model provides simple backing storage for the shared bus.
- A request is accepted when `mem_req_valid` and `mem_req_ready` are both high at the active clock edge.
- For a write command, the model stores `mem_req_wdata` at the requested address.
- For a read command, the model returns the stored data for the requested address through `mem_resp_rdata` and asserts `mem_resp_valid` when the response is available.
- The initial model supports one accepted request at a time; request acceptance and response timing must be defined consistently with the shared bus.
- Storage organization, address and data widths, command encodings, reset behaviour of the stored memory, and read-response latency must be agreed before the interface is frozen.
