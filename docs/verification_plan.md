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
- READ of peer M with delayed dirty-data write acceptance before requester fill.
- Dirty victim writeback under backpressure while the other core requests that victim address.
- Simultaneous different-line requests; verify fixed cache-0 priority, both responses, and per-core data.
- Snoop-filter hit on a known absent address.

These scenarios passed in the current workspace with Icarus Verilog 11.0. The integration bench directly instantiates `mesi_controller`, `snoop_filter`, and two `l1_cache` modules; its backing memory is inline testbench logic. The L1 source used was `/tmp/l1_cache.v` outside the repository; its provenance as the team's agreed source cannot be established from repository contents. There is no standalone shared-bus or main-memory module in the integration run; those blocks remain unverified. See [the integration README](../tb/integration/README.md) for the exact commands and dependency details.

The controller unit test passed with checks for read-request backpressure, M-to-S dirty-write backpressure, stable memory request payloads, and exactly-once write/fill behavior. The snoop-filter unit test passed with `FILTER_ENTRIES=0`, `4`, and `16`.

Still planned: same-address adjacent-cycle requests, all coherence scenarios with `FILTER_ENTRIES=0` and other capacities, standalone shared-bus and main-memory verification, and a reproducible integration run using L1 RTL committed or otherwise supplied with the project.

## Evidence

Record simulator version, command, pass/fail result, and commit hash in PR notes. Do not record a test as passing until it has actually run.
