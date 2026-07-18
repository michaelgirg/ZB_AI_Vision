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

## Production-v2 Expansion

The July 10 percentage remains historical evidence only. The production-v2
eleven-test regression adds bins and crosses for all AXI write orderings and
strobes, repeated-address read freshness, access responses, RAL register and
field behavior, frame/error/stall diagnostics, interrupt enable/status/IRQ,
malformed packets, reset recovery, randomized runtime prediction, and legal
recovery after errors. This plan originally preceded the licensed-server run;
the final eleven-test coverage results are recorded below.

### July 17 production-v2 randomized closure

After correcting the sticky-`done` assertion, the runtime predictor cleanly
completed all 100 recorded seeds (1 through 100). Every seed reached
`RANDOM_PREDICTOR_PASS` with zero UVM errors and zero UVM fatals. The merged
assertion report had zero failures, including 100 passes of the corrected
done-causality property, and coverage reporting ended with zero errors and zero
warnings.

The random-only merged report measured 68.33% covergroup coverage and 35.78%
filtered instance coverage. These are supporting stress metrics, not the
production closure metric: protocol-error, RAL, diagnostics, malformed-packet,
and reset scenarios are intentionally outside the randomized predictor seed
family. The subsequent clean eleven-test UCDB merge is recorded below.

### July 17 eleven-test clean pass and gap analysis

The corrected regression passed all eleven tests with zero UVM errors/fatals,
zero simulator errors, zero assertion failures, and a successful UCDB merge.
Merged covergroup coverage was 93.09%: output-stream coverage was 100%, while
control coverage was 86.19%. Every address, strobe, response, write-ordering,
and response cross closed.

The 17 missing control bins were all diagnostic-state samples: individual and
combined sticky error/interrupt values, three mixed interrupt-enable masks, and
error-count values one and saturated. The closure update now:

- reads packet, rejected-write, rejected-read, and combined sticky causes;
- samples done+packet and done+access interrupt combinations, then isolates the
  individual W1C causes;
- checks error counts at zero, one, two, and three events;
- writes all individual, mixed, all-enabled, and disabled interrupt masks;
- defines combined status as one meaningful bin without overlapping individual
  status bins; and
- excludes only `ERROR_COUNT == 0xffff_ffff` from dynamic functional coverage,
  because reaching it requires 2^32 production error events. Saturation is
  checked by the `production_diag_sva` simulation assertion; a formal proof is
  not claimed.

The Questa `vopt-13408` warning only reports that code coverage cannot be
instrumented for some DUs/packages/classes; the run had `UVM_WARNING : 0`. Raw
filtered instance coverage (50.51%) still includes inactive baseline modes,
interface toggles, defensive paths, and tool instrumentation limits, so it is a
review metric rather than the functional release gate. The targeted closure
rerun passed with 100.00% total covergroup coverage. Both covergroup instances,
every targeted coverpoint, and every targeted cross report 100%; all assertion
failure counts are zero.
