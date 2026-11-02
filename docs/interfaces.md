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

## `shared_bus` — frozen interface

The shared bus acts as a serialized bridge between the MESI controller and the main memory model. Core-level request arbitration is handled by the MESI controller, not by this module.

| Signal | Direction | Width | Meaning |
|---|---|---:|---|
| `clk` | input | 1 | Rising-edge clock. |
| `rst_n` | input | 1 | Active-low asynchronous reset. |
| `ctrl_req_valid` | input | 1 | Controller presents a memory request. |
| `ctrl_req_write` | input | 1 | `0` = READ, `1` = WRITE. |
| `ctrl_req_addr` | input | 16 | Address for the memory operation. |
| `ctrl_req_wdata` | input | 32 | Data supplied for a write operation. |
| `ctrl_req_ready` | output | 1 | Indicates that the controller request has been accepted. |
| `mem_req_valid` | output | 1 | Bus presents a request to the memory model. |
| `mem_req_write` | output | 1 | `0` = READ, `1` = WRITE. |
| `mem_req_addr` | output | 16 | Address forwarded to memory. |
| `mem_req_wdata` | output | 32 | Write data forwarded to memory. |
| `mem_req_ready` | input | 1 | Memory model indicates it can accept a request. |
| `mem_resp_valid` | input | 1 | Memory model indicates that read data is available. |
| `mem_resp_rdata` | input | 32 | Read data returned by memory. |
| `ctrl_resp_valid` | output | 1 | Read response is available to the controller. |
| `ctrl_resp_rdata` | output | 32 | Read data returned to the controller. |

**Behaviour notes:**

- The bus supports one outstanding memory transaction at a time.
- A memory request is accepted when `mem_req_valid` and `mem_req_ready` are both high at the rising clock edge.
- The bus forwards the controller's request to memory and maintains stable request signals while waiting for memory acceptance.
- A write completes when `mem_req_valid && mem_req_ready` is sampled high at the rising clock edge. No separate write response is generated.
- A read is accepted through the same handshake. Its response is forwarded later through `ctrl_resp_valid` and `ctrl_resp_rdata`.
- The bus does not perform core-level arbitration; the MESI controller handles request arbitration.
- Address width is 16 bits and data width is 32 bits.
- Controller request signals must remain stable while `ctrl_req_valid` is high and `ctrl_req_ready` is low.

## `main_memory_model` — frozen interface

| Signal | Direction | Width | Meaning |
|---|---|---:|---|
| `clk` | input | 1 | Rising-edge clock. |
| `rst_n` | input | 1 | Active-low asynchronous reset. |
| `mem_req_valid` | input | 1 | Indicates that a memory request is being presented. |
| `mem_req_write` | input | 1 | `0` = READ, `1` = WRITE. |
| `mem_req_addr` | input | 16 | Address for the memory operation. |
| `mem_req_wdata` | input | 32 | Data to be written for a write operation. |
| `mem_req_ready` | output | 1 | Indicates that the memory model can accept a request. |
| `mem_resp_valid` | output | 1 | Indicates that read data is available. |
| `mem_resp_rdata` | output | 32 | Read data returned by the memory model. |

**Behaviour notes:**

- A request is accepted when `mem_req_valid` and `mem_req_ready` are both high at the rising clock edge.
- `mem_req_write = 0` indicates a READ operation; `mem_req_write = 1` indicates a WRITE operation.
- For a WRITE, the model stores `mem_req_wdata` at the requested address when the request is accepted. No separate write response is generated.
- For a READ, the model returns the stored data through `mem_resp_rdata` and asserts `mem_resp_valid` when the response is available.
- The initial model supports one outstanding memory transaction at a time.
- Request signals must remain stable while `mem_req_valid` is high and `mem_req_ready` is low.
- Address width is 16 bits and data width is 32 bits.
- The backing storage is initialized for simulation. Stored memory contents do not need to be cleared during reset.
- Read-response latency is implementation-defined, but the response must be generated after the read request is accepted.
