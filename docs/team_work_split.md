# Suggested Work Split (4 Teammates)

Keep module ports agreed in `interfaces.md` before parallel implementation.

## Pranshu — Snoop filter
- Own `rtl/coherence/snoop_filter.v` and `tb/unit/tb_snoop_filter.v`.
- Validate zero-entry bypass, lookup, insert/remove, clear, and replacement.
- Deliver a short note explaining why false-negative snoop suppression is forbidden.

## Nandana — L1 cache
- Propose/freeze cache line format, tag/index slicing, state encoding, and request/response handshake.
- Implement private cache storage/control in `rtl/cache/`.
- Add isolated cache unit tests in `tb/unit/`.

## Charan— MESI/coherence controller
- Write state transition table and bus transaction table first.
- Implement controller in `rtl/coherence/` (separate from the filter).
- Define exact filter update events and snoop suppression conditions.

## Talha— Shared bus, memory model, integration
- Implement serialized arbitration and a simple backing-memory model.
- Build integration harness and multi-core scenarios.
- Maintain `tb/integration/` and simulation instructions.

## Integration rule

The top-level integrator owns the shared interface contract. Changes to ports, state encodings, address interpretation, or transaction ordering must be discussed and documented before merging.
