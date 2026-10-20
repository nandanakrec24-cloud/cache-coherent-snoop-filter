# Architecture Overview

## Intended top-level path

`core0 request` / `core1 request` → private L1 cache controllers → coherence controller / snoop filter → serialized shared bus → backing memory.

This is a planned architecture, not a statement that all blocks are already implemented.

## Baseline parameters

| Parameter | Baseline |
|---|---:|
| Number of cores | 2 |
| Address width | 16 bits, word-addressed |
| Data width | 32 bits |
| L1 lines per core | 8 |
| L1 mapping | Direct mapped |
| Coherence | MESI |
| Filter | Fully associative exclusive negative filter |
| Filter sizes to evaluate | 0, 4, 16 entries |

## Address interpretation

Addresses are word addresses. The baseline uses 8 lines per cache, so the direct-mapped index requires 3 bits. The remaining address bits form the tag. Confirm exact tag/index slicing with the team before implementing cache arrays.

## Filter semantics

`filter_hit = 1` means the queried address is recorded as absent from both private caches. `snoop_required = 1` on a filter miss. The filter stores negative knowledge, not cache tags or MESI states.

The filter is a performance optimization. The coherence protocol must remain correct when `FILTER_ENTRIES=0`.
