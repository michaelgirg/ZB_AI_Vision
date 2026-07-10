# Learned INT8 3x3 Convolution Modes

## Goal

Add a learned fixed-point convolution primitive to the AXI4-Stream/DMA
preprocessing accelerator without replacing the stable threshold and Sobel
modes.

Current DMA modes:

```text
MODE=0 threshold
MODE=1 Sobel
MODE=2 learned INT8 3x3 convolution
MODE=3 four-filter learned INT8 vector convolution
```

This is intentionally one learned filter and one output feature map. It is a
hardware/software co-design step toward CNN-style preprocessing, not a full CNN
accelerator.

## Stream Contract

The DMA stream contract stays unchanged:

```text
TDATA width: 32 bits
pixel payload: TDATA[7:0]
TKEEP: 4'b1111
TLAST: final pixel of the 28x28 frame
MODE=2 output: M_AXIS_TDATA[7:0]
MODE=3 output: filters 0, 1, 2, 3 packed in successive output bytes
```

The frame size is still:

```text
IMAGE_WIDTH  = 28
IMAGE_HEIGHT = 28
IMAGE_PIXELS = 784
```

## Fixed-Point Math

Pixels remain unsigned 8-bit values. Kernel coefficients are signed INT8.
Accumulation uses signed INT32.

For each interior pixel:

```text
acc = bias
acc += pixel[y-1][x-1] * k00
acc += pixel[y-1][x  ] * k01
acc += pixel[y-1][x+1] * k02
acc += pixel[y  ][x-1] * k10
acc += pixel[y  ][x  ] * k11
acc += pixel[y  ][x+1] * k12
acc += pixel[y+1][x-1] * k20
acc += pixel[y+1][x  ] * k21
acc += pixel[y+1][x+1] * k22
scaled = acc >>> shift
if relu_enable and scaled < 0: scaled = 0
output = clamp(scaled, 0, 255)
```

Border pixels are forced to zero, matching the Sobel convention.

## Current Learned Filter

The first learned-filter configuration is defined in:

```text
pytorch/preprocess.py
generated/headers/learned_conv_config.h
generated/test_vectors/learned_conv_manifest.json
```

Current values:

```text
kernel = [
  [-2, -1,  0],
  [-1,  6,  1],
  [ 0,  1,  2],
]
bias = -128
shift = 3
relu_enable = 1
```

The kernel behaves like a learned stroke-enhancement filter. It is not a Sobel
copy; it uses asymmetric signed coefficients and a learned-style bias/scale.

## AXI-Lite Register Additions

The convolution mode adds these registers:

```text
0x30 CONV_K00
0x34 CONV_K01
0x38 CONV_K02
0x3c CONV_K10
0x40 CONV_K11
0x44 CONV_K12
0x48 CONV_K20
0x4c CONV_K21
0x50 CONV_K22
0x54 CONV_BIAS
0x58 CONV_SHIFT
0x5c CONV_RELU_EN
```

Kernel register writes use the low 8 bits as signed INT8 values. Bias is a
signed 32-bit value. Shift uses bits `[4:0]`. ReLU enable uses bit `0`.

The top latches all convolution parameters when `CTRL.start` is accepted. This
prevents software writes during an active DMA frame from corrupting the current
operation.

## Four-Filter MODE=3 Architecture

`axis_conv3x3_vector4_preprocess.sv` shares one rolling 3x3 line-buffer window
across four learned filters. Each interior pixel launches 36 signed INT8
products in parallel, followed by pipelined per-filter adder trees, signed
INT32 bias, arithmetic shift, optional ReLU, uint8 saturation, and four-byte
packing. Border outputs remain zero.

```text
M_AXIS_TDATA[7:0]   = filter 0
M_AXIS_TDATA[15:8]  = filter 1
M_AXIS_TDATA[23:16] = filter 2
M_AXIS_TDATA[31:24] = filter 3
M_AXIS_TKEEP        = 4'b1111
M_AXIS_TLAST        = final pixel of the 28x28 frame
```

The vector top uses indexed shadow configuration:

```text
0x60 VECTOR_CFG_INDEX
0x64 VECTOR_CFG_DATA
0x68 VECTOR_CFG_COMMIT
0x6c VECTOR_CFG_VERSION
```

`VECTOR_CFG_INDEX[5:4]` selects filter 0-3. Index entries 0-8 select kernel
taps, entry 9 selects signed bias, and entry 10 selects shift in bits `[4:0]`
plus ReLU enable in bit 8. A commit copies the complete shadow bank into the
committed bank only while idle. Start snapshots the committed bank into active
frame configuration, so software writes cannot change an in-flight frame.

## Verification Status

Python golden export:

```text
pytorch/export_learned_conv.py --all-samples
```

Generated vectors:

```text
generated/test_vectors/sample_000_conv.mem
...
generated/test_vectors/sample_007_conv.mem
```

Passing RTL simulations:

```text
axis_conv3x3_preprocess_tb: PASS, 784/784 pixels matched, 17438 cycles
axis_conv3x3_parallel_preprocess_tb: PASS, 784/784 pixels matched, 892 cycles
axis_preprocess_axi_lite_tb +MODE=2: PASS, 784/784 pixels matched, 888 cycles
```

Existing threshold and Sobel top-level stream simulations still pass after the parallel mode-2 update.

Four-filter verification status:

```text
axis_conv3x3_vector4_preprocess_tb: PASS, 784/784 packed outputs, 892 cycles
axis_preprocess_vector_axi_lite_tb +MODE=3: PASS, 784/784 packed outputs, 888 cycles
MODE=0/1/2 regressions through the vector top: PASS
AXI4-Stream vector UVM tests: 4/4 PASS
Targeted vector UVM functional coverage: 100.00%, 52/52 combined bins
UVM errors/fatals: 0/0
Assertion failures: 0
```

The separate Ultra96 MODE=3 Vivado checkpoint is under
`vivado/u96_dma_vec4_vivado`. Synthesis passes with `+6.985 ns` WNS, zero TNS,
zero failing endpoints, `11243` LUTs, `12281` registers, `3` BRAM tiles, and
`45` DSP48E2 blocks. That DSP total is 9 retained for MODE=2 plus 36 for
MODE=3. Implementation closes at `+4.413 ns` WNS and `+0.015 ns` hold slack
with zero TNS/failing endpoints. Final utilization is `10359` LUTs, `11903`
registers, `3` BRAM tiles, and `45` DSPs; DRC is clean and the dedicated XSA
export passes.

The hardened parallel path uses a bounded 32-entry elastic FIFO, a registered INT32 accumulator stage before scaling and activation, and DSP inference attributes on all nine signed products. Ultra96-V1 implementation maps the products to 9 DSP48E2 blocks, closes timing with `+5.456 ns` WNS at 100 MHz, and uses 6631 CLB LUTs, 8172 CLB registers, and 3 BRAM tiles.

## Sobel vs Learned Conv

Sobel is a handcrafted gradient detector. It is deterministic, explainable, and
uses fixed coefficients chosen by a human.

The learned convolution mode uses configurable INT8 coefficients, signed bias,
fixed-point scaling, optional ReLU, and saturation. That makes it closer to how
CNN first-layer feature extraction is deployed in embedded AI accelerators.


