# Results

## Hardware MVP

| Item | Result |
| --- | --- |
| Board | ZedBoard |
| Device | XC7Z020-CLG484-1 |
| Input samples | `sample_000` through `sample_007` |
| FPGA preprocessing | PASS |
| FPGA Sobel preprocessing | PASS |
| Baseline classifier prediction | PASS |
| Advanced classifier prediction | PASS |
| Fixed-point logits | PASS |
| Final result | PASS |

## Timing

Current board-validated hardware measurement with the 142.857 MHz pipelined
Sobel bitstream:

| Path | Cycles | Notes |
| --- | ---: | --- |
| FPGA threshold preprocessing | 786 | Measured by `image_preprocess_engine` cycle counter |
| FPGA Sobel preprocessing | 898 | Measured by pipelined `image_sobel_engine` cycle counter |
| ARM-only threshold preprocessing | 15,928 | Average across 8 samples, measured with `XTime_GetTime()` |
| Threshold speedup | 20.26x | ARM threshold cycles divided by FPGA threshold cycles |
| ARM threshold-model inference | 782,948 | Average `784 -> 64 -> 10` fixed-point MLP |
| ARM threshold+Sobel inference | 3,791,988 | Average `1568 -> 96 -> 10` fixed-point MLP |
| Advanced inference ratio | 4.84x | Advanced inference cycles divided by threshold-model cycles |

The FPGA cycle count is expected:

```text
784 pixels + 2 pipeline/control cycles = 786 cycles
```

At common clock rates, this corresponds to:

| Clock | Approx. FPGA preprocessing time |
| ---: | ---: |
| 50 MHz | 15.72 us |
| 100 MHz | 7.86 us |
| 150 MHz | 5.24 us |
| 200 MHz | 3.93 us |

Previous pre-pipeline ZedBoard UART timing:

```text
Samples passed: 8/8
Avg ARM threshold preprocess cycles: 15848
Avg FPGA threshold preprocess cycles: 786
Avg FPGA Sobel preprocess cycles: 897
Threshold preprocessing speedup: 20.16x
```

Current 142.857 MHz pipelined Sobel UART timing:

```text
Samples passed: 8/8
Avg ARM threshold preprocess cycles: 15928
Avg FPGA threshold preprocess cycles: 786
Avg FPGA Sobel preprocess cycles: 898
Expected pipelined Sobel cycles: 898
Threshold preprocessing speedup: 20.26x
```

The Vitis app now also reports ARM inference timing:

```text
Validation Summary
Samples passed: 8/8
Avg threshold model inference cycles: 782948
Avg advanced model inference cycles: 3791988
Advanced inference ratio: 4.84x threshold model
```

## RTL Simulation

| Testbench | Samples | Result |
| --- | ---: | --- |
| `sobel_core_tb` | 8 | PASS |
| `image_sobel_engine_tb` | 8 | PASS |
| `image_preprocess_reg_block_tb` mode 0 threshold | 8 | PASS |
| `image_preprocess_reg_block_tb` mode 1 Sobel | 8 | PASS |
| `image_preprocess_axi_lite_tb` mode 0 threshold | 8 | PASS |
| `image_preprocess_axi_lite_tb` mode 1 Sobel | 8 | PASS |

Current Sobel core result:

```text
PASS: Sobel core matched 784 pixels with 3-cycle datapath latency.
```

Current full-image Sobel engine result:

```text
PASS: Sobel engine matched 784 pixels in 898 cycles.
```

Current AXI-visible mode results:

```text
threshold mode: 786 cycles
Sobel mode:     898 cycles
```

Current board-validated mode-register validation:

```text
FPGA threshold: PASS
FPGA Sobel: PASS
FPGA threshold cycles: 786
FPGA Sobel cycles: 898
Result: PASS
```

## Vivado Implementation

The cleaned Sobel-enabled implementation meets timing at the baseline 100 MHz
PL clock and the higher-clock experiments through an actual 142.857 MHz:

| Metric | 100 MHz Baseline | 111.111 MHz | 125 MHz | 142.857 MHz |
| --- | ---: | ---: | ---: | ---: |
| Clock period | 10.000 ns | 9.000 ns | 8.000 ns | 7.000 ns |
| WNS | +0.961 ns | +0.518 ns | +0.229 ns | +0.427 ns |
| TNS | 0.000 ns | 0.000 ns | 0.000 ns | 0.000 ns |
| Failing endpoints | 0 | 0 | 0 | 0 |
| Hold slack | +0.086 ns | +0.090 ns | +0.071 ns | +0.106 ns |
| Slice LUTs | 966 / 53,200, 1.82% | 946 / 53,200, 1.78% | 957 / 53,200, 1.80% | 946 / 53,200, 1.78% |
| Slice Registers | 1,107 / 106,400, 1.04% | 1,117 / 106,400, 1.05% | 1,117 / 106,400, 1.05% | 1,192 / 106,400, 1.12% |
| Block RAM Tiles | 1.5 / 140, 1.07% | 1.5 / 140, 1.07% | 1.5 / 140, 1.07% | 1.5 / 140, 1.07% |
| DSPs | 0 / 220, 0.00% | 0 / 220, 0.00% | 0 / 220, 0.00% | 0 / 220, 0.00% |
| Power estimate | 1.683 W | 1.685 W | 1.687 W | 1.691 W |

The output-buffer cleanup moved the image buffer into RAMB18 resources and
removed the previous setup violation. The later Sobel address cleanup moved the
worst setup path into the actual Sobel arithmetic datapath.

A requested 150 MHz FCLK setting produced an actual 142.857 MHz PL clock before
the latest Sobel input-window pipeline stage. That pre-pipeline implementation
did not meet timing:

| Metric | 142.857 MHz Pre-Pipeline |
| --- | ---: |
| Clock period | 7.000 ns |
| WNS | -0.602 ns |
| TNS | -4.455 ns |
| Failing setup endpoints | 13 |
| Hold slack | +0.097 ns |

The RTL now includes one extra Sobel input-window pipeline stage. Retesting the
same requested 150 MHz setting produced an actual 142.857 MHz clock and met
timing with `WNS +0.427 ns`.

See:

```text
docs/timing_closure.md
```

## Quantized Classifier

### Threshold Baseline

| Metric | Result |
| --- | ---: |
| Fixed-point test accuracy | 94.68% |
| Float/fixed prediction agreement | 99.84% |
| Max dequantized logit error | 0.3057 |

Generated artifacts:

```text
generated/headers/model_weights_quantized.h
generated/headers/model_quantized_golden.h
generated/model/quantized_metrics.json
```

### Threshold + Sobel Upgrade

| Metric | Result |
| --- | ---: |
| Input features | 1568 |
| Model shape | `1568 -> 96 -> 10` |
| Float test accuracy | 95.94% |
| Fixed-point test accuracy | 95.98% |
| Float/fixed prediction agreement | 99.86% |
| Max dequantized logit error | 0.2210 |

Generated artifacts:

```text
generated/model/metrics_threshold_sobel.json
generated/model/threshold_sobel_quantized_metrics.json
generated/headers/model_weights_threshold_sobel_quantized.h
generated/headers/model_threshold_sobel_quantized_golden.h
```

The trained `.pt` checkpoint is intentionally excluded from the public copy and
can be regenerated with the PyTorch training script.

ARM deployment status:

```text
Vitis app build: PASS
Public source: vitis/advanced_classifier.c
Model input: FPGA threshold image + FPGA Sobel image
Board validation: PASS
8-sample board validation: PASS
```
