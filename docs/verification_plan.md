# Verification Plan

## Unit tests — snoop filter

- Empty filter lookup misses.
- Insert then lookup hits.
- Unrelated address misses.
- Remove makes a previously stored address miss.
- Duplicate insertion does not duplicate state.
- Fill all entries and exercise replacement.
- Clear all entries.
- `FILTER_ENTRIES=0` always misses and always requires snoop.
- Reset clears all valid bits.

## Integration tests — current bench coverage

- Core-visible reads, clean sharing, and upgrade invalidation.
- UPGRADE contract: verify the L1 raises `MISS_UPGRADE` for an accepted write hit in S, retains the requester S line through the peer snoop until fill, the peer is invalidated, and no memory read is issued for the retained line.
- READ of peer M with delayed dirty-data write acceptance before requester fill.
- Dirty victim writeback under backpressure while the other core requests that victim address.
- Simultaneous different-line requests; verify fixed cache-0 priority, both responses, and per-core data.
- Snoop-filter hit on a known absent address.

The integration bench directly instantiates `mesi_controller`, `snoop_filter`, and two `l1_cache` modules; its backing memory is inline testbench logic. The tracked L1 was recovered from repository history (commit `ec6b950`). The previous external `/tmp/l1_cache.v` files were absent when this revision was prepared, so identity with the source used in the earlier reported run remains unknown. There is no standalone shared-bus or main-memory module in the integration run; those blocks remain unverified. See [the integration README](../tb/integration/README.md) for reproducible commands.

The controller unit test passed with checks for read-request backpressure, M-to-S dirty-write backpressure, stable memory request payloads, and exactly-once write/fill behavior. The snoop-filter unit test passed with `FILTER_ENTRIES=0`, `4`, and `16`.

Still planned: same-address adjacent-cycle requests, all coherence scenarios with `FILTER_ENTRIES=0` and other capacities, standalone shared-bus and main-memory verification.

## Evidence

Record simulator version, command, pass/fail result, and commit hash in PR notes. Do not record a test as passing until it has actually run.
