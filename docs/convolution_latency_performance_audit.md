# Convolution Latency and Performance Audit

This note tracks the learned INT8 3x3 convolution accelerator revisions. The goal is to keep the project honest: pixel-correct simulation is not enough if the hardware path cannot close timing or move pixels efficiently.

## Architecture Revisions

| Revision | Main idea | Questa MODE=2 cycles | Timing status |
| --- | --- | ---: | --- |
| Combinational conv | Read 3x3 window and compute output in one cycle after frame buffering | 1677 | Failed implementation timing |
| Conservative MAC | Sequential RAM read, multiply, and accumulate stages | 22851 | Timing-clean first conv DMA build |
| Optimized overlapped MAC | Accumulate previous product while reading next pixel | 17433 | Timing-clean optimized conv DMA build |
| Parallel line-buffer conv | 3 line buffers, ordered output events, 9 parallel INT8 multiplies, pipelined adder/scaling path | 888 | Ultra96 impl WNS +5.456 ns; timing clean |
| Four-filter vector conv | Shared 3x3 window, 36 parallel INT8 multiplies, four packed output channels | 888 | Ultra96 impl WNS +4.413 ns; timing clean |

The optimized overlapped MAC reduced selectable top convolution latency by `5418` cycles compared with the conservative MAC path, or about `23.7%`.

The parallel line-buffer convolution reduces selectable top convolution latency from `17433` cycles to `888` cycles, or about `94.9%`. That changes MODE=2 from about `22.2` cycles/pixel to about `1.13` cycles/pixel in the current backpressure-enabled testbench.

## Why The Optimized Conv Was Still Slow

1. The optimized convolution path was still serial at the 3x3 window level. It buffered the whole frame, then processed each output pixel through a tap loop.
2. Each interior pixel still paid roughly one read/accumulate and one multiply step per tap, plus scale, ReLU, clamp, and output handshaking.
3. `s_axis_tready` was high during frame receive, but then the input stream was complete and the core spent most cycles in internal compute/output states.
4. `m_axis_tvalid` only appeared after each serialized per-pixel computation, so output initiation interval was far above 1.
5. The testbench cycle counter is real operation latency from the first accepted input beat to the final output beat. It includes the same input gaps and output backpressure across revisions, which makes the comparison fair.
6. The effective output initiation interval of the optimized MAC path was still above 20 cycles/pixel for the full frame.
7. The extra cycles came from replaying 676 interior pixels through a serial 9-tap MAC schedule after the 784-pixel input frame had already been received.

## Parallel Line-Buffer Architecture

The new `axis_conv3x3_parallel_preprocess.sv` revision keeps the DMA stream contract unchanged:

```text
TDATA[7:0] = pixel
TKEEP = 4'b1111
TLAST = final 28x28 pixel
```

The core uses three 28-pixel line buffers and a rolling row modulo index to form each 3x3 window as pixels arrive. Border pixels are emitted as ordered zero events. Interior pixels go through a parallel fixed-point pipeline:

```text
window capture -> 9 parallel INT8 multiplies -> adder tree -> bias/shift/ReLU/clamp -> output FIFO
```

A 32-entry elastic output FIFO decouples the compute pipeline from AXI4-Stream output backpressure. It stores only the 8-bit pixel and TLAST flag and reserves eight entries for in-flight pipeline events. The accumulator is registered before the configurable shift, ReLU, and saturation stage, and the nine product registers request DSP implementation. When the FIFO has space, the input side can continue accepting one pixel per cycle. Bottom-row border zeros are flushed after the final input beat and after the convolution pipeline drains.

## Latest Questa Results

| Test | Result | Processing cycles |
| --- | --- | ---: |
| Old standalone optimized conv | PASS | 17438 |
| Hardened standalone parallel conv | PASS | 892 |
| Selectable top MODE=2 parallel conv | PASS | 888 |
| Selectable top MODE=0 threshold | PASS | 889 |
| Selectable top MODE=1 Sobel | PASS | 2576 |
| Standalone four-filter vector conv | PASS | 892 |
| Selectable vector top MODE=3 | PASS | 888 |

MODE=3 produces four learned scalar features per output beat, so it delivers
`3136` feature values per 784-pixel frame at essentially the same simulation
latency as the single-filter MODE=2 path. The expected tradeoff is approximately
36 DSP48E2 multipliers plus larger per-filter reduction and activation logic.
Measured post-route PPA is summarized below and in `docs/ppa_comparison.md`.

## Vivado Results So Far

These numbers come from `scripts/read_dma_conv_reports.ps1`.

| Design | Impl WNS | Impl TNS | Failing endpoints | LUTs | FFs | BRAM | DSP | DRC error/critical lines |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Stable threshold/Sobel DMA | 2.953 ns | 0.000 ns | 0 | 4452 | 6066 | 3 | 0 | 0 |
| First convolution DMA | 1.512 ns | 0.000 ns | 0 | 4979 | 6583 | 3.5 | 0 | 0 |
| Optimized convolution DMA | 1.054 ns | 0.000 ns | 0 | 4981 | 6584 | 3.5 | 0 | 0 |
| Ultra96-V1 parallel convolution DMA | 5.456 ns | 0.000 ns | 0 | 6631 | 8172 | 3 | 9 | 0 |
| Ultra96-V1 four-filter vector DMA | 4.413 ns | 0.000 ns | 0 | 10359 | 11903 | 3 | 45 | 0 |

The separate MODE=3 Ultra96 project synthesizes with `+6.985 ns` WNS, zero TNS,
and zero failing endpoints. Synthesis utilization is `11243` LUTs, `12281`
registers, `3` BRAM tiles, and `45` DSP48E2 blocks. The total DSP count is the
expected 9 retained for MODE=2 plus 36 added for MODE=3. Implementation values
close at `+4.413 ns` WNS, `+0.015 ns` hold slack, zero TNS, and zero failing
endpoints. Post-implementation utilization is `10359` LUTs, `11903` registers,
`3` BRAM tiles, and `45` DSP48E2 blocks, with zero DRC error/critical-warning
lines.

The first convolution DMA build added about `527` LUTs, `517` FFs, and `0.5` BRAM tiles over the stable threshold/Sobel DMA design while keeping timing clean. The optimized convolution DMA build kept essentially the same resource footprint as the first convolution build, adding only `2` LUTs and `1` FF after implementation.

### Pre-Hardening Parallel Synthesis Snapshot

The first ZedBoard parallel-convolution synthesis completed at 100 MHz with `+0.036 ns` WNS, zero TNS, and zero failing endpoints. It used `25037` top-level LUTs, `15360` top-level FFs, `3` BRAM tiles, and `0` DSPs. A hierarchical report showed that `conv_path` alone consumed `19969` LUTs and `8532` FFs.

That resource spike came from the original `IMAGE_PIXELS + 8` output FIFO. Because the FIFO allowed two writes in one cycle, Vivado implemented its compact pixel payload as registers and muxes instead of block memory. The multiplier logic also remained in LUT fabric, and the combined accumulator, variable shift, ReLU, and clamp path left almost no synthesis timing margin.

The current RTL supersedes that snapshot. It uses a 32-entry FIFO, a separate accumulator pipeline stage, and DSP inference attributes. Ultra96-V1 synthesis and implementation now pass.

### Ultra96-V1 Hardened Synthesis

The hardened Ultra96-V1 design synthesized successfully at the current 100 MHz PL target:

| WNS | TNS | Failing endpoints | CLB LUTs | CLB registers | BRAM tiles | DSP48E2 |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| +6.985 ns | 0.000 ns | 0 | 7456 | 8646 | 3 | 9 |

The nine learned-convolution products now map to all nine intended DSP48E2 blocks. Compared with the pre-hardening ZedBoard snapshot, the design no longer burns nearly half of the smaller device on a register-based frame FIFO, and the synthesis timing margin is no longer marginal.

### Ultra96-V1 Implementation Checkpoint

Implementation completed with `+5.456 ns` WNS, zero TNS, zero failing endpoints, and zero DRC error/critical-warning lines. Post-implementation utilization is `6631` CLB LUTs, `8172` CLB registers, `3` BRAM tiles, and `9` DSP48E2 blocks. The bitstream and hardware platform were exported successfully.

## Build Artifacts

| Revision | XSA | Status |
| --- | --- | --- |
| Stable threshold/Sobel DMA | `vivado/zedboard_ai_vision_dma.xsa` | Built |
| First convolution DMA | `vivado/zedboard_ai_vision_dma_conv.xsa` | Built |
| Optimized convolution DMA | `vivado/zedboard_ai_vision_dma_conv_opt.xsa` | Built |
| Parallel convolution DMA | `vivado/zedboard_ai_vision_dma_conv_parallel.xsa` | Pending manual Vivado build |
| Ultra96-V1 parallel convolution DMA | `vivado/ultra96_v1_ai_vision_dma_conv_parallel.xsa` | Built, timing clean, XSA exported |
| Ultra96-V1 four-filter vector DMA | `vivado/ultra96_v1_ai_vision_dma_vec4.xsa` | Built, timing clean, XSA exported |

The measured single-filter versus MODE=3 table is maintained in
`docs/ppa_comparison.md`.

