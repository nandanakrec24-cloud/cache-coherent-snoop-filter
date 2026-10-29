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
