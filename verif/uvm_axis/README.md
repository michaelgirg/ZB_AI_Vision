# AXI4-Stream Vector UVM Environment

This separate UVM environment verifies the four-filter `MODE=3` data plane in
`axis_preprocess_vector_axi_lite`. It leaves the stable non-UVM and AXI-Lite UVM
flows unchanged.

## Components

- AXI4-Lite agent for control/configuration transactions
- AXI4-Stream source sequencer and driver
- randomized AXI4-Stream sink backpressure driver
- independent input and output monitors
- packed four-channel pixel scoreboard
- control and stream functional coverage collectors
- AXI4-Stream protocol/frame assertions

## Tests

- `vector4_stream_test`: programs and commits all 44 learned parameters, then
  compares 784 packed outputs against the Python golden frame.
- `vector4_backpressure_test`: repeats the frame with randomized output
  backpressure.
- `vector4_busy_write_test`: attempts index, data, commit, mode, and start writes
  while processing is active and proves the in-flight frame is not corrupted.
- `vector4_saturation_test`: programs a deterministic clamp configuration and
  verifies all interior channels saturate to `255`, while frame borders remain
  zero.

The control sequence also changes an uncommitted shadow weight after commit.
Matching the committed golden frame verifies shadow/commit atomicity.

## UF Server Regression

From `~/zb-ai-vision-verif`:

```bash
source /apps/reconfig/enable_std
bash verif/uvm_axis/run_server_regression.sh
```

The script compiles with coverage, runs all four tests using real
`+UVM_TESTNAME` selection, checks the UVM summaries and scoreboard pass line,
merges the UCDBs, and writes `vector_coverage_report.txt`.

## Current Status

The July 10, 2026 UF closure run passed all four tests with zero UVM errors,
fatals, scoreboard mismatches, or assertion failures. The stream and control
functional covergroups both reached 100.00% targeted coverage (26/26 bins
each). The raw filtered code/toggle result is documented separately and is not
the release metric for this focused MODE=3 verification plan.
