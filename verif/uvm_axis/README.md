# Production Vector AXI UVM Environment

This environment verifies `axis_preprocess_vector_axi_lite` as reusable SoC IP,
with emphasis on the packed four-filter mode and its control-plane contract.

## Components

- active AXI4-Lite agent with independent AW/W timing;
- UVM RAL block, adapter, monitor-driven predictor, and v2 register model;
- AXI4-Stream source and randomized-backpressure sink agents;
- independent input/output monitors;
- fixed-file scoreboard plus runtime arithmetic predictor;
- protocol, frame, stall-stability, FIFO, TLAST, done, and error assertions;
- stream/control functional coverage including WSTRB, ordering, response, RAL,
  configuration, saturation, malformed packet, and recovery scenarios.

## Release tests

| Test | Primary purpose |
| --- | --- |
| `vector4_stream_test` | committed model versus 784 packed golden outputs |
| `vector4_backpressure_test` | randomized downstream stalls |
| `vector4_busy_write_test` | in-flight configuration/start/commit rejection |
| `vector4_saturation_test` | signed extremes, ReLU, low/high clamp |
| `vector4_diagnostics_test` | counters, sticky/W1C status, rejected accesses, interrupt masking and IRQ |
| `vector4_wstrb_test` | all 16 byte-strobe combinations and command gating |
| `vector4_axi_protocol_test` | AW-first, W-first, simultaneous, repeated-address freshness, misaligned/unmapped/RO/WO responses |
| `vector4_ral_test` | reset/readback/bit-bash including v2 identity/counter/IRQ registers |
| `vector4_random_predictor_test` | random legal image and configuration against runtime predictor |
| `vector4_packet_recovery_test` | early/missing TLAST, bad TKEEP, post-error recovery |
| `vector4_reset_recovery_test` | reset during stalled output and clean recovery |

`run_server_multiseed.sh` repeats the randomized predictor test with recorded
seeds. The default is 100.

## Commands

```bash
source /apps/reconfig/enable_std
bash verif/uvm_axis/run_server_regression.sh
SEED_COUNT=100 bash verif/uvm_axis/run_server_multiseed.sh
```

Both scripts fail on compile failure, nonzero UVM error/fatal counts, a missing
pass marker, assertion-failure text, or coverage-tool failure.

## Evidence boundary

The July 10, 2026 legacy four-test regression passed 4/4 with zero UVM
errors/fatals/assertion failures and 100% of its then-targeted 52 functional
bins. That result remains historical baseline evidence.

The expanded production-v2 environment compiles locally with zero errors and
warnings. On July 17, 2026, its randomized predictor passed all 100 recorded
seeds with zero UVM errors/fatals and zero merged assertion failures. Random-only
covergroup coverage was 68.33%; this is supporting stress evidence, not a v2
closure claim. The eleven-test execution and merged production coverage review
subsequently passed on the licensed school server: all 11 markers, zero UVM
errors/fatals, zero simulator errors, zero assertion failures, and a successful
UCDB merge. After targeted diagnostic-state sampling, the closure rerun reports
100.00% total covergroup coverage: both stream and control instances, every
targeted coverpoint, and every targeted cross are 100%. Illegal protocol bins
remain unhit as required. The sole ignored dynamic bin is the 2^32-event
counter-saturation state, which remains a simulation-assertion obligation; no
formal proof is claimed.

The RAL model represents `ERROR_STATUS` and `INT_STATUS` as UVM `RW` fields for
compatibility with UVM 1.1d, whose register package rejects `W1C` as an access
string during build. The actual hardware semantics remain W1C and are checked
directly by `vector4_diagnostics_test`; the server regression is the authority
for that behavior.
