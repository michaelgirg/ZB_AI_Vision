# Vector Stream Coverage Plan

## Scope

This plan covers the `MODE=3` four-filter learned INT8 convolution path in `axis_preprocess_vector_axi_lite`. It is separate from the stable AXI-Lite UVM coverage plan.

## Targeted Functional Coverage

| Area | Bins | Test source |
| --- | --- | --- |
| AXI4-Stream output | full `TKEEP`, first/interior/last beats | directed and backpressure tests |
| Backpressure | none, 1-2 cycles, 3+ cycles; border/interior cross | directed and backpressure tests |
| Feature outputs | zero, active 1-254, saturated 255 for all four channels | learned-frame and saturation tests |
| Vector configuration | all 4 filters, 9 taps, bias, shift/ReLU | directed test |
| Register traffic | legal writes and reads for control/status/configuration | directed and busy-write tests |
| Atomic configuration | committed configuration survives an uncommitted shadow update | directed test |
| Busy protection | index/data/commit/mode/start writes during active processing | busy-write test |

## Assertions

- Input and output `TKEEP` must remain full.
- `TDATA`, `TKEEP`, and `TLAST` must remain stable while output is stalled.
- Input and output `TLAST` must occur only on beat 783 of a 28x28 frame.

## UF Server Results

On July 10, 2026, the initial three-test regression passed:

```text
vector4_stream_test: PASS, 784/784 packed outputs
vector4_backpressure_test: PASS, 784/784 packed outputs
vector4_busy_write_test: PASS, 784/784 packed outputs
UVM_ERROR: 0
UVM_FATAL: 0
Assertion failures: 0
```

The raw combined covergroup result was 76.18%. The stream coverage itself was 85.18% because the trained test frames did not naturally saturate to 255. The control collector also used an unconstrained integer/cross model, causing 504 meaningless auto bins.

## Closure Run

The July 10, 2026 four-test closure regression passed:

```text
Compile: PASS, 0 errors, 0 warnings
vector4_stream_test: PASS, 784/784 packed outputs
vector4_backpressure_test: PASS, 784/784 packed outputs
vector4_busy_write_test: PASS, 784/784 packed outputs
vector4_saturation_test: PASS, 784/784 packed outputs
UVM_ERROR: 0
UVM_FATAL: 0
Assertion failures: 0
Targeted stream covergroup: 100.00%, 26/26 bins
Targeted control covergroup: 100.00%, 26/26 bins
Total targeted covergroup coverage: 100.00%
```

The saturation test exercised all four channels through zero, active, and
saturated output bins. The refined control model also closed every legal
read/write, filter, tap, bias, shift/ReLU, and mode bin.

The raw filtered code/toggle result was 47.72%. It includes interface toggles,
baseline modes, wide register fields, and defensive RTL paths outside this
focused MODE=3 test plan. It is recorded as a secondary metric, not a release
gate. The closure metric is 100% of the targeted functional bins plus zero
scoreboard mismatches, UVM errors/fatals, and assertion failures.
