# Two-cache MESI integration testbench

## Testbench composition and scope

`tb_mesi_l1_integration` directly instantiates:

- One `mesi_controller`.
- One `snoop_filter` (`FILTER_ENTRIES=4`).
- Two `l1_cache` instances, `c0` and `c1`.

The testbench implements a simple synchronous backing-memory process inline. It does **not** instantiate a standalone `shared_bus` or `main_memory_model`; neither standalone module is present in this repository, and both remain unverified. Passing this test is not full-system verification.

The L1 source used in the last recorded run was `/tmp/l1_cache.v`, which is outside the repository. It matches the ports instantiated here and holds miss requests until fill and victim writebacks until acknowledgement. An identical `/tmp/l1_cache.v.bak` is also present. Its provenance as the team's agreed source cannot be established from repository contents. The source is not committed, so the integration test cannot be reproduced from a clean checkout until the agreed L1 RTL is added or made available at that path. Do not replace it with a test-only cache stub and call that full integration verification.

## Scenarios covered

- Core-visible read response data for both caches.
- Clean sharing, upgrade invalidation, and reading a modified peer line.
- M-to-S dirty-data writeback with delayed memory acceptance; stable write controls/address/data, peer invalidation, no early fill, one accepted write, and latest-data response are checked.
- Dirty-victim writeback under backpressure while the other core reads that victim address; the writeback must be accepted and acknowledged before the competing read completes with the newest data.
- Simultaneous requests for different lines; cache 0 is expected to win the controller's fixed-priority arbitration, both requests must complete, and each core must receive its own line data.
- Dirty victim replacement and resulting MESI state.

Each wait in the core request tasks has a cycle limit, and the testbench has a global timeout.

## Recorded verification

Last run: Icarus Verilog 11.0. The controller unit test, snoop-filter unit tests at capacities 0, 4, and 16, and the integration test all printed `PASS` in the current workspace. The integration result depends on the external `/tmp/l1_cache.v` source described above. Icarus emitted `@*` array-sensitivity warnings for nonzero filter capacities; they did not fail the tests.

```sh
cd /tmp
mkdir -p build
iverilog -g2012 -I /home/pichu/cache-coherent-snoop-filter/rtl/common \
  -o /tmp/tb_mesi_controller.vvp \
  /home/pichu/cache-coherent-snoop-filter/rtl/coherence/mesi_controller.v \
  /home/pichu/cache-coherent-snoop-filter/tb/unit/tb_mesi_controller.v
vvp /tmp/tb_mesi_controller.vvp

iverilog -g2012 -I /home/pichu/cache-coherent-snoop-filter/rtl/common \
  -o /tmp/tb_snoop_filter.vvp \
  /home/pichu/cache-coherent-snoop-filter/rtl/coherence/snoop_filter.v \
  /home/pichu/cache-coherent-snoop-filter/tb/unit/tb_snoop_filter.v
vvp /tmp/tb_snoop_filter.vvp

iverilog -g2012 -s tb_snoop_filter -Ptb_snoop_filter.FILTER_ENTRIES=0 \
  -I /home/pichu/cache-coherent-snoop-filter/rtl/common \
  -o /tmp/tb_snoop_filter_0.vvp \
  /home/pichu/cache-coherent-snoop-filter/rtl/coherence/snoop_filter.v \
  /home/pichu/cache-coherent-snoop-filter/tb/unit/tb_snoop_filter.v
vvp /tmp/tb_snoop_filter_0.vvp

iverilog -g2012 -s tb_snoop_filter -Ptb_snoop_filter.FILTER_ENTRIES=16 \
  -I /home/pichu/cache-coherent-snoop-filter/rtl/common \
  -o /tmp/tb_snoop_filter_16.vvp \
  /home/pichu/cache-coherent-snoop-filter/rtl/coherence/snoop_filter.v \
  /home/pichu/cache-coherent-snoop-filter/tb/unit/tb_snoop_filter.v
vvp /tmp/tb_snoop_filter_16.vvp

iverilog -g2012 -I /home/pichu/cache-coherent-snoop-filter/rtl/common \
  -o /tmp/tb_mesi_l1_integration.vvp \
  /home/pichu/cache-coherent-snoop-filter/rtl/coherence/mesi_controller.v \
  /home/pichu/cache-coherent-snoop-filter/rtl/coherence/snoop_filter.v \
  /tmp/l1_cache.v \
  /home/pichu/cache-coherent-snoop-filter/tb/integration/tb_mesi_l1_integration.v
vvp /tmp/tb_mesi_l1_integration.vvp
```

Run the commands from `/tmp` so the testbench VCD files are created under `/tmp/build`, not in the repository. The standalone bus and standalone memory implementations still need their own tests and an integrated top-level verification before making full-system claims.
