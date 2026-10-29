# L1 Cache (`l1_cache.v`)

**Owner:** Nandana

A private, direct-mapped L1 cache that tracks a MESI state for every line.
The top level uses **two copies** of this module, one per core.

## What it stores

8 lines. Each line has:

| Field | Bits | Meaning |
|---|---:|---|
| Tag | 13 | Which address is stored in this line |
| Data | 32 | The value |
| State | 2 | MESI state (`I` = empty) |

There is no separate valid bit: state `I` means the line is empty.

### Address split (16-bit word address)

| Bits | Name | Use |
|---|---|---|
| `[2:0]` | index | Picks one of the 8 lines |
| `[15:3]` | tag | Compared with the stored tag to detect a hit |

### Encodings

| MESI state | Code | | Miss request | Code |
|---|---|---|---|---|
| I | `00` | | READ | `00` |
| S | `01` | | RDX (read-for-ownership) | `01` |
| E | `10` | | UPGRADE | `10` |
| M | `11` | | | |

## What it does

| Situation | Action |
|---|---|
| Read hit (M/E/S) | Return data next cycle |
| Write hit in M | Write, stay M |
| Write hit in E | Write, become M (no bus traffic) |
| Write hit in S | Send UPGRADE, wait for `fill_valid`, write, become M |
| Read miss | Send READ, install line in `fill_state` (E or S) |
| Write miss | Send RDX, install line, write, become M |
| Miss evicting an M line | Write the old line back first (`wb_req_*`), then send the miss |
| Read snoop hit | Report state + data; M/E become S |
| Invalidating snoop hit | Report state + data; become I |

Internally this is a 3-state machine: **IDLE → (WB) → MISS → IDLE**.

## Handshakes

- **Core:** a request is accepted on a rising edge when `core_req_valid && core_req_ready`.
  `core_resp_valid` pulses for one cycle when it finishes (`core_resp_rdata` holds read data).
- **Miss:** `miss_req_valid` stays high until the controller pulses `fill_valid` for one cycle.
- **Writeback:** `wb_req_valid` stays high until the controller pulses `wb_ack` for one cycle.
- **Snoop:** `snoop_valid` is a one-cycle request. `snoop_hit`, `snoop_state`
  (state before the snoop) and `snoop_data` are combinational, so they're valid in the same cycle.
  The state update happens on that cycle's rising edge.

## Contract with the coherence controller

These rules must be followed by the controller (Charan) and integration (Talha):

1. For READ, `fill_state` must be **E** (no other copy) or **S** (other copy exists).
   For RDX and UPGRADE, `fill_state` is ignored and the line becomes M.
2. For UPGRADE, if the other core's request invalidated our copy while we waited,
   the controller must treat the request as RDX and put the real line in `fill_data`.
3. Do not assert `snoop_valid` and `fill_valid` to the same cache in the same cycle.
4. While `snoop_valid` is high, `core_req_ready` is low (the core is stalled for that cycle).
5. When a snoop hits a line in M, the controller must take `snoop_data`. It is the only up-to-date copy.

## Parameters

| Parameter | Default |
|---|---:|
| `ADDR_WIDTH` | 16 |
| `DATA_WIDTH` | 32 |
| `NUM_LINES` | 8 (must be a power of 2) |

## Status

- Unit test: `tb/unit/tb_l1_cache.v` passes (Icarus Verilog).
- Yosys synthesis: no latches. The "replacing memory with registers" warnings
  are expected, because 8 lines are small enough to build from flip-flops.
