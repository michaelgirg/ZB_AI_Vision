# Ultra96 Convolution PPA Comparison

This table compares the stable single-filter Ultra96 parallel-convolution checkpoint with the completed four-filter MODE=3 vector-convolution revision. Both columns use measured synthesis and post-implementation results.

| Metric | Single-filter parallel conv | Four-filter vector conv |
| --- | ---: | ---: |
| Supported modes | 0, 1, 2 | 0, 1, 2, 3 |
| Learned output channels per pixel | 1 | 4 packed bytes |
| Output beat width | 32 bits, feature in `[7:0]` | 32 bits, filters 0-3 in `[7:0]` through `[31:24]` |
| Scalar features per frame | 784 | 3136 |
| Selectable-top Questa cycles | 888 | 888 |
| Standalone core Questa cycles | 892 | 892 |
| Parallel multiplier allocation | 9 for MODE=2 | 9 for MODE=2 + 36 for MODE=3 |
| Synthesis WNS | +6.985 ns | +6.985 ns |
| Synthesis TNS | 0.000 ns | 0.000 ns |
| Synthesis failing endpoints | 0 | 0 |
| Synthesis LUTs | 7456 | 11243 |
| Synthesis registers | 8646 | 12281 |
| Synthesis BRAM tiles | 3 | 3 |
| Synthesis DSP48E2 | 9 | 45 |
| Implementation WNS | +5.456 ns | +4.413 ns |
| Implementation TNS | 0.000 ns | 0.000 ns |
| Implementation failing endpoints | 0 | 0 |
| Implementation LUTs | 6631 | 10359 |
| Implementation registers | 8172 | 11903 |
| Implementation BRAM tiles | 3 | 3 |
| Implementation DSP48E2 | 9 | 45 |
| DRC error/critical-warning lines | 0 | 0 |
| XSA | `vivado/ultra96_v1_ai_vision_dma_conv_parallel.xsa` | `vivado/ultra96_v1_ai_vision_dma_vec4.xsa` |

## Architectural Interpretation

Both pipelines target one accepted input pixel per cycle and one output beat per cycle after fill. MODE=3 reuses one 3x3 window generator across four learned filters, performs 36 signed INT8 products in parallel, and packs four uint8 activations into each output beat. Therefore its frame latency stays approximately equal to the single-filter path while useful learned-feature throughput rises from one to four scalar channels per beat.

The MODE=3 synthesis adds exactly 36 DSP48E2 blocks while preserving the 9-DSP
MODE=2 path, for 45 total. Relative to the single-filter checkpoint, synthesis
adds 3787 LUTs (`+50.8%`) and 3635 registers (`+42.0%`) with no BRAM increase.
Synthesis WNS remains `+6.985 ns`, with zero TNS and zero failing endpoints.
After routing, MODE=3 adds 3728 LUTs (`+56.2%`) and 3731 registers (`+45.7%`)
over the single-filter checkpoint, with BRAM unchanged and 36 additional DSPs.
Implementation closes at `+4.413 ns` setup WNS and `+0.015 ns` hold slack, with
zero TNS, zero failing endpoints, and zero DRC error/critical-warning lines.

## Release Criteria

- Synthesis and implementation WNS must be nonnegative.
- TNS and failing endpoints must be zero.
- DRC must contain zero error or critical-warning lines.
- DSP mapping should be inspected against the 36-multiplier architecture.
- The XSA exports to the dedicated MODE=3 path without replacing the stable single-filter XSA.
- Existing MODE=0/1/2 simulations and the MODE=3 packed-output scoreboard remain passing.

All release criteria are satisfied for the MODE=3 Vivado checkpoint.
