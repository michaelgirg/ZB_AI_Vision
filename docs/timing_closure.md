# Timing Closure Notes

## Current Finding

The first Sobel-enabled Vivado implementation routed successfully, but did not
meet the 100 MHz PL clock target. After the output-buffer cleanup, the rerun
meets timing at 100 MHz. After the Sobel address-path cleanup, the design also
meets timing at 9.000 ns and 8.000 ns PL clock periods. After adding the Sobel
input-window pipeline stage, the design meets timing at a 7.000 ns PL clock
period.

Best passing implementation so far:

```text
Requested FCLK_CLK0: 150 MHz
Actual FCLK_CLK0: 142.857 MHz
Period target: 7.000 ns
Worst negative slack: +0.427 ns
Total negative slack: 0.000 ns
Failing endpoints: 0
Hold slack: +0.106 ns
Pulse-width slack: +2.250 ns
Timing status: MET
```

Worst setup path at 142.857 MHz after the extra Sobel pipeline stage:

```text
Source: AXI SmartConnect address register
Destination: AXI SmartConnect AXI-Lite address register
Data path delay: 6.555 ns
Logic levels: 9
Path type: AXI interconnect address/control path
```

The Sobel BRAM-to-gradient path is no longer the worst path after the extra
pipeline stage.

Previous passing implementation:

```text
Clock: clk_fpga_0
Period target: 8.000 ns
Frequency target: 125.000 MHz
Worst negative slack: +0.229 ns
Total negative slack: 0.000 ns
Failing endpoints: 0
Hold slack: +0.071 ns
Pulse-width slack: +2.750 ns
Timing status: MET
```

Worst setup path at 125.000 MHz:

```text
Source: input_mem RAMB18E1 output
Destination: sobel_core gy_r register
Data path delay: 7.703 ns
Logic levels: 8
Path type: BRAM read into Sobel gradient arithmetic
```

Higher-clock implementation:

```text
Clock: clk_fpga_0
Period target: 9.000 ns
Frequency target: 111.111 MHz
Worst negative slack: +0.518 ns
Total negative slack: 0.000 ns
Failing endpoints: 0
Hold slack: +0.090 ns
Pulse-width slack: +3.250 ns
Timing status: MET
```

Worst setup path at 111.111 MHz:

```text
Source: input_mem RAMB18E1 output
Destination: sobel_core gy_r register
Data path delay: 8.303 ns
Logic levels: 7
Path type: BRAM read into Sobel gradient arithmetic
```

This is a better bottleneck than the previous border-address/output-buffer path:
the design is now limited by real Sobel datapath work rather than avoidable
address decode and memory inference behavior.

Pre-pipeline 150 MHz request:

```text
Requested FCLK_CLK0: 150 MHz
Actual FCLK_CLK0: 142.857 MHz
Period target: 7.000 ns
Worst negative slack: -0.602 ns
Total negative slack: -4.455 ns
Failing setup endpoints: 13
Hold slack: +0.097 ns
Timing status: NOT MET
```

Worst setup path at 142.857 MHz before the extra Sobel pipeline stage:

```text
Source: input_mem RAMB18E1 output
Destination: sobel_core gy_r/gx_r registers
Data path delay: 7.499 ns
Logic levels: 7
Path type: BRAM read into Sobel gradient arithmetic
```

Post-cleanup timing:

```text
Clock: clk_fpga_0
Period target: 10.000 ns
Frequency target: 100.000 MHz
Worst negative slack: +0.961 ns
Total negative slack: 0.000 ns
Failing endpoints: 0
Hold slack: +0.086 ns
Timing status: MET
```

Pre-cleanup timing:

```text
Clock: clk_fpga_0
Period target: 10.000 ns
Worst negative slack: -1.098 ns
Timing status: NOT MET
```

Worst reported path:

```text
Source: image_sobel_engine border index register
Destination: output image buffer register
Data path delay: 10.915 ns
Logic levels: 13
Issue: output buffer inferred as registers instead of RAM
```

Vivado also reported:

```text
output_mem_reg implemented in registers
```

Pre-cleanup placed utilization:

| Resource | Used | Available | Utilization |
| --- | ---: | ---: | ---: |
| Slice LUTs | 12,780 | 53,200 | 24.02% |
| Slice Registers | 7,423 | 106,400 | 6.98% |
| Block RAM Tiles | 1 | 140 | 0.71% |
| DSPs | 0 | 220 | 0.00% |

Post-cleanup placed utilization:

| Resource | Used | Available | Utilization |
| --- | ---: | ---: | ---: |
| Slice LUTs | 966 | 53,200 | 1.82% |
| Slice Registers | 1,107 | 106,400 | 1.04% |
| Block RAM Tiles | 1.5 | 140 | 1.07% |
| DSPs | 0 | 220 | 0.00% |

111.111 MHz placed utilization after Sobel address cleanup:

| Resource | Used | Available | Utilization |
| --- | ---: | ---: | ---: |
| Slice LUTs | 946 | 53,200 | 1.78% |
| Slice Registers | 1,117 | 106,400 | 1.05% |
| Block RAM Tiles | 1.5 | 140 | 1.07% |
| DSPs | 0 | 220 | 0.00% |

111.111 MHz power estimate:

```text
Total on-chip power: 1.685 W
Junction temperature: 44.4 C
Confidence level: Medium
```

125.000 MHz placed utilization after Sobel address cleanup:

| Resource | Used | Available | Utilization |
| --- | ---: | ---: | ---: |
| Slice LUTs | 957 | 53,200 | 1.80% |
| Slice Registers | 1,117 | 106,400 | 1.05% |
| Block RAM Tiles | 1.5 | 140 | 1.07% |
| DSPs | 0 | 220 | 0.00% |

125.000 MHz power estimate:

```text
Total on-chip power: 1.687 W
Junction temperature: 44.5 C
Confidence level: Medium
```

142.857 MHz placed utilization after Sobel input-window pipeline:

| Resource | Used | Available | Utilization |
| --- | ---: | ---: | ---: |
| Slice LUTs | 946 | 53,200 | 1.78% |
| Slice Registers | 1,192 | 106,400 | 1.12% |
| Block RAM Tiles | 1.5 | 140 | 1.07% |
| DSPs | 0 | 220 | 0.00% |

142.857 MHz power estimate:

```text
Total on-chip power: 1.691 W
Junction temperature: 44.5 C
Confidence level: Medium
```

Route status:

```text
fully routed nets: 2197 / 2197
routing errors: 0
```

## RTL Cleanup Applied

`rtl/image_preprocess_buffered.sv` was updated so the output image buffer has a
single muxed write port shared by threshold and Sobel engines.

Goal:

```text
threshold write path
Sobel write path
        -> single output RAM write port
        -> host output read port
```

This should reduce wide register-array write decode fanout and help Vivado map
the output buffer as RAM instead of a large FF/LUT structure.

## Higher-Frequency Prep

`rtl/image_sobel_engine.sv` was also cleaned up for the next Fmax experiment.
This is intended for targets above the current 100 MHz PL clock.

Changes:

```text
1. Replaced combinational Sobel border address generation with a registered
   border address counter.
2. Removed the border_addr() row/column decode from the output RAM address path.
3. Replaced Sobel center pixel address multiplication with a counter-derived
   address: current_pixel_index - (IMAGE_WIDTH + 1).
```

Why this helps:

```text
old border write path:
border_index -> row/column decode -> row*IMAGE_WIDTH + col -> output RAM address

new border write path:
border_addr_r -> output RAM address
```

This does not change Sobel latency or output values. It only removes avoidable
combinational logic from a path that can matter when the PL clock is pushed
higher than 100 MHz.

## Sobel Datapath Pipeline

After the 142.857 MHz implementation failed, `rtl/sobel_core.sv` was updated
with a registered 3x3 input-window stage before the Gx/Gy arithmetic.
`rtl/image_sobel_engine.sv` was updated with one more center-address pipeline
stage so output writes remain aligned with `valid_out`.

Tradeoff:

```text
Sobel core latency: 2 cycles -> 3 cycles
Full-image Sobel latency: 897 cycles -> 898 cycles
Expected timing benefit: break BRAM-output-to-gradient-register critical path
```

## Simulation After Cleanup

```text
vlog -sv -f tb/filelist.f
PASS: buffered threshold mode, 786 cycles
PASS: buffered Sobel mode, 897 cycles
PASS: AXI-Lite Sobel mode
```

After the higher-frequency prep change:

```text
vlog -sv -f tb/filelist.f
PASS: buffered threshold sample_000, 786 cycles
PASS: buffered Sobel samples sample_000 through sample_007, 897 cycles each
PASS: AXI-Lite Sobel sample_000
```

After the Sobel input-window pipeline change:

```text
vlog -sv -f tb/filelist.f
PASS: Sobel core sample_000, 3-cycle datapath latency
PASS: Sobel engine sample_000, 898 cycles
PASS: buffered threshold sample_000, 786 cycles
PASS: buffered Sobel samples sample_000 through sample_007, 898 cycles each
PASS: register block Sobel sample_000, 898 cycles
PASS: AXI-Lite Sobel sample_000
```

## Final Validation

The target timing and board-validation result is now achieved:

```text
Timing constraints met at 142.857 MHz actual PL clock
WNS: +0.427 ns
Board validation: PASS
FPGA threshold cycles: 786
FPGA pipelined Sobel cycles: 898
Samples passed: 8/8
```

Recorded artifacts:

```text
Bitstream/XSA: zedboard_ai_vision_pipelined_sobel
Results summary: docs/results.md
```
