# RTL

Current module:

```text
threshold_core.sv
sobel_core.sv
image_preprocess_engine.sv
image_sobel_engine.sv
image_preprocess_buffered.sv
image_preprocess_reg_block.sv
image_preprocess_axi_lite.sv
axis_preprocess_pkg.sv
axis_preprocess_if.sv
axis_threshold_preprocess.sv
axis_sobel_preprocess.sv
axis_conv3x3_preprocess.sv
axis_preprocess_axi_lite.sv
```

`threshold_core.sv` is the standalone threshold datapath for Milestone 2.

`sobel_core.sv` is the standalone pipelined 3x3 Sobel datapath. It registers
gradient sums, edge magnitude, and saturated output so the arithmetic has a
clean path to higher Fmax.

`image_preprocess_engine.sv` builds on that core and processes a complete image using an external memory-style interface. It is intentionally not AXI-connected yet. First we prove the engine against Python golden vectors; then we wrap it with image buffers and PS/PL control.

`image_sobel_engine.sv` streams one input pixel per clock through two line
buffers, uses `sobel_core.sv` for the arithmetic pipeline, writes zero border
pixels, and writes Sobel interior pixels by output address.

`image_preprocess_buffered.sv` adds internal input/output image buffers and simple host-facing load/read ports. This is the step before replacing those host ports with AXI-Lite/BRAM access.

`image_preprocess_reg_block.sv` adds the planned software-visible register
flow around the buffered block. It is not a full AXI-Lite slave yet; it is the
register/control layer that a later AXI-Lite wrapper will drive.

`image_preprocess_axi_lite.sv` is the Vivado-facing top for Zynq PS/PL
integration. It wraps the register block with an AXI4-Lite slave interface.

`axis_preprocess_pkg.sv` and `axis_preprocess_if.sv` define the interface
contract for the next AXI4-Stream/DMA architecture milestone. They are not part
of the current AXI4-Lite hardware top yet.

`axis_threshold_preprocess.sv` is the first AXI4-Stream datapath for the DMA
architecture milestone. It accepts one 8-bit pixel per AXI4-Stream beat,
applies the threshold kernel, preserves packet boundaries with `tlast`, and
supports downstream backpressure through `tready`.

`axis_sobel_preprocess.sv` is the AXI4-Stream packet wrapper for Sobel mode. It
receives one full image packet into an internal buffer, reuses
`image_sobel_engine.sv`, then streams one Sobel output packet back out with
valid/ready backpressure support.

`axis_conv3x3_preprocess.sv` is the learned INT8 3x3 convolution stream path. It
buffers one input image packet, applies signed INT8 coefficients with signed
INT32 bias/accumulation, shifts/scales, optionally applies ReLU, clamps to
uint8, and forces border pixels to zero.

`axis_preprocess_axi_lite.sv` is the DMA-oriented top. It exposes AXI4-Lite
configuration/status registers, selects threshold, Sobel, or learned
convolution mode, arms one AXI4-Stream image packet with `CTRL.start`, and
routes the processed stream to `M_AXIS`.

The core is a one-cycle registered pipeline:

```text
valid_in, pixel_in, threshold
  -> compare/mux
  -> valid_out, pixel_out
```

The Sobel core is a two-cycle datapath from window input to valid output:

```text
3x3 window
  -> registered Gx/Gy
  -> registered abs(Gx)+abs(Gy)
  -> saturated 8-bit edge output
```

The engine target is one beat per clock:

```text
start
  -> read one input beat per cycle
  -> threshold pipeline
  -> write one output beat per cycle
  -> done + processing_cycles
```

The Sobel engine target is one input pixel per clock:

```text
start
  -> write zero border pixels
  -> read image raster stream
  -> maintain two line buffers + row shift registers
  -> run pipelined Sobel core for interior pixels
  -> done + processing_cycles
```

The register block target flow is:

```text
write input buffer beats
write mode: 0 threshold, 1 Sobel
write threshold
pulse CTRL.start
poll STATUS.done
read PROCESSING_CYCLES
read output buffer beats
```

Current AXI-visible modes:

```text
0 = threshold image
1 = Sobel edge image
```

The hardware integration top is:

```text
image_preprocess_axi_lite
```

The next architecture target is:

```text
AXI4-Lite config/status
AXI4-Stream input packet
AXI4-Stream output packet
AXI DMA moving image buffers between DDR and PL
```

See `docs/axi_stream_dma_architecture.md` for the packet contract and
verification plan.
