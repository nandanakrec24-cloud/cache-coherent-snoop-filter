# Unit Testbenches

Each block is tested on its own here before integration.

| Testbench | Block under test | Owner |
|---|---|---|
| `tb_snoop_filter.v` | `rtl/coherence/snoop_filter.v` | Pranshu |
| `tb_l1_cache.v` | `rtl/cache/l1_cache.v` | Nandana |

## How to run (Icarus Verilog)

Run from the repository root:

```bash
mkdir -p build

# L1 cache
iverilog -g2005 -o build/tb_l1_cache.vvp tb/unit/tb_l1_cache.v rtl/cache/l1_cache.v
vvp build/tb_l1_cache.vvp

# Snoop filter (try FILTER_ENTRIES = 0, 4, 16)
iverilog -g2005 -P tb_snoop_filter.FILTER_ENTRIES=4 \
  -o build/tb_snoop_filter.vvp tb/unit/tb_snoop_filter.v rtl/coherence/snoop_filter.v
vvp build/tb_snoop_filter.vvp
```

A passing run prints `PASS: ...`. A failing run prints each `FAIL` line and exits with an error.
Waveforms are written to `build/*.vcd` and can be opened in GTKWave.

## `tb_l1_cache.v`

The testbench pretends to be both the **core** and the **coherence controller**:

- A fake memory (`mem`) starts with `mem[a] = {16'hA5A5, a}`, so every address has a recognizable value.
- A fake controller answers miss requests after 3 cycles, using the state set in `next_fill_state`.
  It accepts writebacks in 1 cycle.
- The tasks `core_access(write, addr, wdata, rdata)` and `snoop(addr, invalidate)` drive the cache.

### What is checked

| # | Test |
|---|---|
| 1 | Reset leaves every line in I |
| 2 | Read miss sends READ; line installed in E with correct data |
| 3 | Read hit makes no bus request |
| 4 | Write hit in E becomes M silently |
| 5 | Conflict miss on an M line writes it back first, then refills in S |
| 6 | Write hit in S sends UPGRADE and ends in M |
| 7 | Write miss sends RDX and ends in M with the written data |
| 8 | Read snoop on M reports M + data and moves the line to S |
| 9 | Invalidating snoop moves the line to I; the next read misses |
| 10 | Snoop to an absent address reports no hit and changes nothing |
| 11 | Race: the line is invalidated while an UPGRADE is waiting; it still ends in M with the right data |
| 12 | The core is stalled (`core_req_ready = 0`) while a snoop is active |

A 20 µs timeout catches any handshake that hangs.
