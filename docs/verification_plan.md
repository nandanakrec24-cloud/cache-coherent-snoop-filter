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

## Integration tests — planned

- Core 0 read, then Core 1 read of same address (clean sharing).
- Core 0 write after both cores hold shared copies (invalidation).
- Core 1 reads a line modified by Core 0 (writeback/forwarding path).
- Two cores request the same address in adjacent cycles.
- Dirty line eviction and memory consistency.
- Filter hit skips a remote snoop only when the address is truly absent from both caches.
- Filter miss performs the normal snoop path.
- Repeat all coherence scenarios with filter disabled and with small filter capacity.

## Evidence

Record simulator version, command, pass/fail result, and commit hash in PR notes. Do not record a test as passing until it has actually run.
