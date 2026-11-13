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
