# Protocol Notes and Invariants

## MESI states

- **M — Modified:** this cache has the only valid copy and it is dirty relative to memory.
- **E — Exclusive:** this cache has the only valid copy and it matches memory.
- **S — Shared:** multiple caches may hold clean copies.
- **I — Invalid:** this cache does not hold a valid copy.

The team must agree on the exact bus transactions and state transitions before the MESI controller is implemented.

## Exclusive negative snoop filter

An entry for address A asserts: **A is absent from both private caches**.

1. On filter hit, the remote snoop can be skipped only if the integration logic preserves the invariant above.
2. On filter miss, snoop as required by the coherence controller.
3. Before any core installs/acquires A, remove A from the filter.
4. Insert A only after both private caches are known to be absent and no fill/ownership grant is pending.
5. A filter eviction removes knowledge only. It must not affect cache state.
6. Duplicate insertion must not create duplicate entries.
7. Removing an address not present must be harmless.
8. `FILTER_ENTRIES=0` means bypass: every lookup misses and every request that relies on the filter must snoop.

## Concurrency and ordering

The initial project serializes shared-bus requests. The integration design must define how simultaneous requests are arbitrated and when filter updates happen relative to snoops, fills, evictions, and ownership grants. Do not infer these timing rules solely from the standalone filter module.
