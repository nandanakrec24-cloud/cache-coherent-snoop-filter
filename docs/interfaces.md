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
