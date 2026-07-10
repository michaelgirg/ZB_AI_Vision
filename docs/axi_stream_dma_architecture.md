# AXI4-Stream and DMA Architecture

## Goal

Upgrade the current AXI4-Lite buffered preprocessing accelerator into a more
realistic Zynq accelerator architecture:

```text
DDR image buffer
  -> AXI DMA MM2S
  -> AXI4-Stream preprocessing IP
  -> AXI DMA S2MM
  -> DDR processed buffer
  -> ARM fixed-point classifier
```

The existing AXI4-Lite design stays as the stable baseline. The stream/DMA path
is a new architecture milestone and should be built in simulation before the
Vivado block design is changed.

## Current Baseline

The current hardware path is register/buffer controlled:

```text
ARM writes pixels through AXI4-Lite registers
ARM writes mode/threshold
ARM starts accelerator
PL reads internal input buffer
PL writes internal output buffer
ARM reads pixels through AXI4-Lite registers
```

That path is validated on board and verified with directed benches plus mini
UVM. It is intentionally kept stable while the streaming path is added.

Current stream status:

```text
axis_preprocess_pkg.sv: compile PASS
axis_preprocess_if.sv: compile PASS
axis_threshold_preprocess.sv: directed threshold/backpressure simulation PASS
axis_sobel_preprocess.sv: directed Sobel/backpressure simulation PASS
axis_preprocess_axi_lite.sv: selectable AXI4-Lite/AXI4-Stream top simulation PASS
axis_conv3x3_preprocess.sv: directed learned-conv/backpressure simulation PASS
```

## Target Streaming Architecture

The next datapath separates control from bulk pixel movement:

```text
AXI4-Lite:
  mode
  threshold
  image size constants
  status/cycle counters

AXI4-Stream input:
  one pixel beat per transfer
  source is AXI DMA MM2S

AXI4-Stream output:
  one processed pixel beat per transfer
  sink is AXI DMA S2MM
```

The first stream implementation should support 28x28 images only, matching the
current MNIST/test-vector contract. Make image dimensions parameters in RTL so
the design can grow later.

## Packet Contract

One image is one AXI4-Stream packet.

```text
IMAGE_WIDTH  = 28
IMAGE_HEIGHT = 28
IMAGE_PIXELS = 784
```

First implementation:

```text
TDATA width: 32 bits
TKEEP width: 4 bits
Pixel payload: TDATA[7:0]
Unused payload bits: TDATA[31:8] = 0
TKEEP: 4'b0001
TLAST: asserted only on pixel index 783
TUSER: not used in MVP
TID/TDEST: not used in MVP
```

The stream core must count accepted input beats:

```text
input_fire = s_axis_tvalid && s_axis_tready
```

and output beats:

```text
output_fire = m_axis_tvalid && m_axis_tready
```

The IP must never consume a pixel unless `s_axis_tvalid && s_axis_tready` is
true, and must never drop an output pixel when `m_axis_tvalid && !m_axis_tready`.

## Modes

The AXI4-Lite mode register should keep the current meaning:

```text
0 = threshold image
1 = Sobel edge image
2 = learned INT8 3x3 convolution image
3 = four-filter packed INT8 3x3 vector image
```

Threshold mode:

```text
input pixel >= threshold -> output 255
else                     -> output 0
```

Sobel mode:

```text
3x3 Sobel edge magnitude
border pixels forced to 0
edge = abs(Gx) + abs(Gy), saturated to 255
```

Learned convolution mode:

```text
signed INT8 3x3 kernel
signed INT32 bias and accumulation
arithmetic right shift scaling
optional ReLU
clamp to uint8 0..255
border pixels forced to 0
```

Four-filter vector mode uses the same 3x3 fixed-point rules for four independent
learned kernels and packs filters 0-3 into `M_AXIS_TDATA[7:0]`, `[15:8]`,
`[23:16]`, and `[31:24]`. One shared window generator feeds 36 parallel signed
INT8 multiplies. `TKEEP` remains `4'b1111`, and `TLAST` remains the final pixel.

## Control Model

The stream accelerator should not require the ARM to write every pixel through
AXI4-Lite. AXI4-Lite should be used for configuration and observability only.

Recommended register behavior:

```text
CTRL.start:
  arms the stream core for exactly one input image packet

STATUS.busy:
  high after start is accepted until the output packet completes

STATUS.done:
  latched when output TLAST is transferred

PROCESSING_CYCLES:
  cycle count from accepted start to output TLAST transfer
```

For DMA integration, software can start S2MM first, then MM2S, then start the
accelerator or use a design where the accelerator begins when the first input
beat arrives after being armed.

## Backpressure Requirements

The stream core must handle:

```text
input stalls:  s_axis_tvalid low
output stalls: m_axis_tready low
mixed stalls:  both sides changing independently
```

Threshold mode can be implemented with a small skid/output register so output
backpressure does not corrupt the pixel sequence.

Sobel mode is more stateful. The first implementation should either:

```text
option A: use an internal image buffer, then stream out after processing
option B: build a fully streaming line-buffer pipeline with valid/ready stalls
```

For the project, choose option A first if schedule risk matters. It still gives
the correct system architecture story:

```text
AXI DMA moves image buffers
PL accelerator receives and emits AXI4-Stream packets
ARM no longer writes one pixel at a time through AXI4-Lite
```

Option B is a later optimization if the project needs a deeper streaming
microarchitecture.

## Recommended Implementation Order

1. Add a stream-only threshold core wrapper. Done.
2. Verify AXI4-Stream handshake, TLAST, and backpressure in simulation. Done for threshold and Sobel.
3. Add stream-to-buffer and buffer-to-stream logic for threshold/Sobel reuse. Done for Sobel.
4. Wrap the existing threshold/Sobel engines behind AXI4-Stream packet I/O. Done for Sobel.
5. Add AXI4-Lite configuration/status around the stream datapath. Done in `axis_preprocess_axi_lite.sv`.
6. Package as Vivado IP.
7. Add AXI DMA to the Zynq block design.
8. Update Vitis software for cache maintenance and DMA transfers.

Vivado wiring notes are in:

```text
docs/axi_dma_vivado_steps.md
```

## Stream Top for Vivado

The top module for the DMA-oriented IP is:

```text
axis_preprocess_axi_lite
```

Interface names:

```text
S_AXI  = AXI4-Lite configuration/status
S_AXIS = AXI4-Stream image input from AXI DMA MM2S
M_AXIS = AXI4-Stream processed output to AXI DMA S2MM
```

Register map:

```text
0x00 CTRL: bit 0 start, bit 1 clear_done
0x04 STATUS: bit 0 busy, bit 1 done, bit 2 packet_error, bit 3 armed
0x08 THRESHOLD
0x0c IMAGE_PIXELS
0x10 PIXELS_PER_CYCLE
0x14 PROCESSING_CYCLES
0x2c MODE: 0 threshold, 1 Sobel, 2 learned conv, 3 four-filter vector conv
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
0x60 VECTOR_CFG_INDEX
0x64 VECTOR_CFG_DATA
0x68 VECTOR_CFG_COMMIT
0x6c VECTOR_CFG_VERSION
```

`CTRL.start` arms exactly one image packet. Before start, `S_AXIS_TREADY` stays
low. After the selected path transfers output `TLAST`, `done` latches and
`PROCESSING_CYCLES` holds the stream operation cycle count.

## Verification Plan

Keep the existing non-UVM and UVM AXI4-Lite regressions unchanged. Add a new
stream verification layer for the stream datapath.

Required stream tests:

```text
threshold_stream_directed_test
sobel_stream_directed_test
tlast_position_test
input_backpressure_test
output_backpressure_test
mixed_backpressure_test
reset_mid_packet_test
short_packet_error_test
extra_pixel_error_test
```

Scoreboard checks:

```text
all 784 output pixels match Python golden vectors
exactly one TLAST per output packet
TLAST occurs on output pixel 783
no output beat appears before a valid input packet is accepted
cycle count is nonzero and stable after done
```

Assertions:

```text
TDATA/TKEEP/TLAST stable while TVALID && !TREADY
input packet has exactly 784 accepted beats
output packet has exactly 784 accepted beats
TLAST only on final beat
done only after output TLAST transfer
busy clears after output packet completion
```

Coverage:

```text
mode threshold/Sobel
input stalls
output stalls
mixed stalls
TLAST final beat
reset idle
reset mid-packet
threshold edge values 0, 1, 127, 128, 254, 255
```

## Vitis DMA Software Contract

The ARM software should eventually use:

```text
input_buffer[784]      aligned in DDR
output_buffer[784]     aligned in DDR
XAxiDma_SimpleTransfer for S2MM
XAxiDma_SimpleTransfer for MM2S
Xil_DCacheFlushRange before MM2S
Xil_DCacheInvalidateRange after S2MM
```

Expected printout after DMA integration:

```text
AXI-Lite register path: PASS
AXI DMA stream path: PASS
FPGA threshold cycles: ...
FPGA Sobel cycles: ...
DMA transfer cycles: ...
ARM preprocessing cycles: ...
AXI-Lite vs DMA speedup: ...
Prediction: ...
Result: PASS
```

## Done Criteria

This architecture milestone is complete when:

```text
AXI4-Stream threshold simulation: PASS
AXI4-Stream Sobel simulation: PASS
AXI4-Stream learned convolution simulation: PASS
AXI4-Lite selectable stream top simulation: PASS
Backpressure simulation: PASS
TLAST assertions: PASS
Vivado packaged IP: PASS
ZedBoard DMA hardware validation: PASS
UART reports DMA preprocessing PASS and classifier PASS
```
