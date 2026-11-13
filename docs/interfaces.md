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

## `l1_cache`

Private direct-mapped cache, one per core. Details: `rtl/cache/README.md`.

**Line format:** 13-bit tag, 32-bit data, 2-bit MESI state (no separate valid bit).
**Address split:** index = `addr[2:0]`, tag = `addr[15:3]`.
**MESI encoding:** I=`00`, S=`01`, E=`10`, M=`11`.
**Miss request types:** READ=`00`, RDX=`01`, UPGRADE=`10`.

| Signal | Direction | Meaning |
|---|---|---|
| `core_req_valid` | input | core has a request |
| `core_req_write` | input | 1 = write, 0 = read |
| `core_req_addr[15:0]` | input | word address |
| `core_req_wdata[31:0]` | input | write data |
| `core_req_ready` | output | request accepted on a rising edge when valid && ready |
| `core_resp_valid` | output | one-cycle pulse when the request is done |
| `core_resp_rdata[31:0]` | output | read data |
| `miss_req_valid` | output | held high until `fill_valid` |
| `miss_req_type[1:0]` | output | READ / RDX / UPGRADE |
| `miss_req_addr[15:0]` | output | missing address |
| `fill_valid` | input | one-cycle pulse: line delivered |
| `fill_data[31:0]` | input | line data |
| `fill_state[1:0]` | input | E or S for READ; ignored for RDX/UPGRADE |
| `wb_req_valid` | output | dirty victim waiting; held until `wb_ack` |
| `wb_req_addr[15:0]` | output | victim address |
| `wb_req_data[31:0]` | output | victim data |
| `wb_ack` | input | one-cycle pulse: writeback done |
| `snoop_valid` | input | one-cycle snoop request |
| `snoop_addr[15:0]` | input | address being snooped |
| `snoop_invalidate` | input | 1 = invalidate, 0 = read snoop (M/E → S) |
| `snoop_hit` | output | combinational: line present |
| `snoop_state[1:0]` | output | combinational: state before the snoop |
| `snoop_data[31:0]` | output | combinational: line data (take it when state is M) |

Controller rules: for an UPGRADE whose copy was invalidated in the meantime, supply the line as for RDX. Never assert `snoop_valid` and `fill_valid` to the same cache in the same cycle.

## Planned interfaces — not yet frozen

- `mesi_controller`: request arbitration, snoop decisions, ownership transfers, filter update events.
- `shared_bus`: serialized command/address/data path.
- `main_memory_model`: request/ready/response interface.
- `ccms_top`: connects two caches, controller, bus, memory, and filter.

Do not code against these planned interfaces until the team freezes their port lists.

<<<<<<< HEAD
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
=======
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
>>>>>>> origin/main
