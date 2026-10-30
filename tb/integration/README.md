# Two-cache MESI integration testbench

## Testbench composition and scope

`tb_mesi_l1_integration` directly instantiates:

- One `mesi_controller`.
- One `snoop_filter` (`FILTER_ENTRIES=4`).
- Two `l1_cache` instances, `c0` and `c1`.

The testbench implements a simple synchronous backing-memory process inline. It does **not** instantiate a standalone `shared_bus` or `main_memory_model`; neither standalone module is present in this repository, and both remain unverified. Passing this test is not full-system verification.

The test instantiates the tracked implementation at `rtl/cache/l1_cache.v`. Its implementation was recovered from repository commit `ec6b950`, with interface comments added for the UPGRADE presence contract. The previously referenced `/tmp/l1_cache.v` and `/tmp/l1_cache.v.bak` were absent in the checkout used for this update, so their identity with the tracked source and the earlier integration run cannot be determined. The integration command below uses only repository files.

## Scenarios covered

- Core-visible read response data for both caches.
- Clean sharing, a Shared-line UPGRADE (including observed `MISS_UPGRADE`, requester S presence at peer snoop, no memory read for the retained copy), and reading a modified peer line.
- M-to-S dirty-data writeback with delayed memory acceptance; stable write controls/address/data, peer invalidation, no early fill, one accepted write, and latest-data response are checked.
- Dirty-victim writeback under backpressure while the other core reads that victim address; the writeback must be accepted and acknowledged before the competing read completes with the newest data.
- Simultaneous requests for different lines; cache 0 is expected to win the controller's fixed-priority arbitration, both requests must complete, and each core must receive its own line data.
- Dirty victim replacement and resulting MESI state.

Each wait in the core request tasks has a cycle limit, and the testbench has a global timeout.

## Recorded verification

Run from the repository root. Simulation binaries and waveforms are written under the ignored `build/` directory.

```sh
mkdir -p build
iverilog -g2012 -I rtl/common \
  -o /tmp/tb_mesi_controller.vvp \
  rtl/coherence/mesi_controller.v tb/unit/tb_mesi_controller.v
vvp /tmp/tb_mesi_controller.vvp

iverilog -g2012 -I rtl/common \
  -o /tmp/tb_snoop_filter.vvp \
  rtl/coherence/snoop_filter.v tb/unit/tb_snoop_filter.v
vvp /tmp/tb_snoop_filter.vvp

iverilog -g2012 -s tb_snoop_filter -Ptb_snoop_filter.FILTER_ENTRIES=0 \
  -I rtl/common \
  -o /tmp/tb_snoop_filter_0.vvp \
  rtl/coherence/snoop_filter.v tb/unit/tb_snoop_filter.v
vvp /tmp/tb_snoop_filter_0.vvp

iverilog -g2012 -s tb_snoop_filter -Ptb_snoop_filter.FILTER_ENTRIES=16 \
  -I rtl/common \
  -o /tmp/tb_snoop_filter_16.vvp \
  rtl/coherence/snoop_filter.v tb/unit/tb_snoop_filter.v
vvp /tmp/tb_snoop_filter_16.vvp

iverilog -g2012 -I rtl/common \
  -o /tmp/tb_mesi_l1_integration.vvp \
  rtl/coherence/mesi_controller.v rtl/coherence/snoop_filter.v \
  rtl/cache/l1_cache.v tb/integration/tb_mesi_l1_integration.v
vvp /tmp/tb_mesi_l1_integration.vvp
```

The unit testbench VCD files are written under `/tmp`; compiled simulations also use `/tmp`. The standalone bus and memory implementations still need their own tests and a top-level integration before making full-system claims. A clean checkout can use the same commands because the L1 source is tracked.
