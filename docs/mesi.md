# MESI Controller — Protocol and Interface Notes

**Owner:** P. Charan
**Status:** Initial controller proposal; cross-module interface still requires team freeze.

## Shared encodings

These encodings match `rtl/cache/l1_cache.v`:

| Item | Encoding |
|---|---|
| Invalid (I) | `00` |
| Shared (S) | `01` |
| Exclusive (E) | `10` |
| Modified (M) | `11` |
| READ miss | `00` |
| RDX (read-for-ownership) miss | `01` |
| UPGRADE miss | `10` |

The initial memory interface uses a separate one-bit command: `0=READ`, `1=WRITE`. Talha must agree to this or update the shared interface contract before integration.

## Transaction rules

- **READ:** obtain the latest data. If the peer has a copy, the requester receives `S`; if no peer copy exists, it receives `E`. If the peer is in `M`, use the peer's `snoop_data`, not stale memory data.
- **RDX:** invalidate the peer's matching line and grant the requester `M`. If the peer is in `M`, use its snoop data; otherwise read the backing memory.
- **UPGRADE:** invalidate the peer and grant `M`. If the requester's own Shared line still exists, the cache keeps its copy and applies its pending write. If the requester copy has disappeared, current line data must be obtained before the grant; the integration must verify this race.
- **Dirty writeback:** send the victim address/data to memory and acknowledge the cache only when the memory accepts the write.
- **Serialization:** this baseline allows one active controller transaction. Dirty writebacks are serviced before a new miss.

## Snoop-filter invariant

A filter hit means the address is known absent from both L1 caches. It is safe to skip a peer snoop only for READ/RDX when that invariant is trusted. UPGRADE does not use a negative-filter hit because the requester normally already holds a copy.

The controller removes the requested address from the negative filter when it accepts a miss, before any fill/ownership grant. The controller does not invent insertion events: `known_absent_insert_valid/address` must only be asserted by integration logic after it proves both caches are absent and no fill or ownership grant is pending. The current L1 interface does not expose every clean-victim eviction, so the team must decide how safe insert events will be generated before claiming full filter optimization.

## Important integration assumptions to freeze

1. `mem_req_ready` accepts both read and write commands on the active clock edge.
2. Writes complete on request acceptance and do not require `mem_resp_valid`; reads complete later with `mem_resp_valid` and `mem_resp_rdata`.
3. `snoop_hit`, `snoop_state`, and `snoop_data` are combinational observations of `snoop_addr`; the target cache updates state on the edge where its `snoop_valid` is asserted.
4. A cache's `fill_valid` pulse is not asserted in the same cycle as `snoop_valid` to that same cache.
5. The top level connects the filter's `filter_hit` to the address on `filter_query_addr` and applies remove/insert outputs at the specified clock edge.
6. Simultaneous misses are serialized. This baseline uses cache 0 priority if both miss-valid inputs rise together; a fair arbitration policy can replace this if the team requires round-robin.

## Known scope limits

- This module is a transaction sequencer proposal, not yet verified with the real two-cache top level, bus, or memory implementation.
- The filter insertion source must be completed at integration because the submitted L1 interface does not report all clean line evictions.
- Standalone testbench results must be run and recorded on the project machine; never claim a pass until the simulator prints `PASS`.

## MESI transition summary

| Current state | Local operation / observed transaction | Required result | Notes |
|---|---|---|---|
| I | Local read miss / READ | E if peer absent; S if peer has a clean copy | If peer is M, source latest data from peer and both become S. |
| I | Local write miss / RDX | M | Peer copy, if any, is invalidated first; latest data is acquired before write completes. |
| S | Local write / UPGRADE | M | Invalidate peer copy before granting write permission. |
| E | Local write hit | M | No bus transaction is needed because this cache was the only clean holder. |
| M | Local read/write hit | M | This cache owns the latest data. |
| E or M | Peer read snoop | S | For M, the controller must capture/forward the latest data. |
| Any valid state | Peer invalidating snoop | I | If the state was M, preserve/forward the dirty data before discarding ownership. |
| S | Peer read snoop | S | Clean shared copy remains shared. |
| I | Any snoop | I | No matching line; no state change. |

This is a protocol summary, not a complete formal transition table for every possible simultaneous event. The serialized controller must prevent conflicting grants and snoops to the same cache in one cycle.

## Bus transaction summary

| L1 request / event | Peer action | Memory action | Requester result |
|---|---|---|---|
| READ, peer absent | Skip only on a trusted negative-filter hit; otherwise read-snoop peer | Read address unless latest data is supplied by peer in M | Fill E when peer absent, S when a peer copy exists |
| READ, peer in M | Read snoop; peer M→S | No memory read required | Fill latest peer data in S |
| RDX, peer clean | Invalidate peer if present | Read address | Fill M |
| RDX, peer in M | Invalidate peer and capture its data | No memory read required | Fill latest peer data in M |
| UPGRADE | Invalidate peer | No memory read if requester copy survives and peer is not M; otherwise acquire current data | Grant M |
| Dirty victim writeback | No peer action from the writeback alone | Write victim address/data; wait for `mem_req_ready` | Pulse matching `wb_ack` after accepted write |

## Review / verification evidence to record

- Simulator and version used.
- Exact compile and run commands.
- Full PASS/FAIL output.
- Commit SHA.
- Explicit note that integration tests with the real L1, bus, memory, and filter remain outstanding until those modules are connected.
