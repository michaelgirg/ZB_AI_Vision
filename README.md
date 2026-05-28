# Zynq AI Vision SoC Pipeline

FPGA-accelerated threshold/Sobel preprocessing plus ARM fixed-point AI inference
on the ZedBoard.

This project uses the Zynq ARM Cortex-A9 processing system to run quantized
PyTorch-trained digit classifiers while custom SystemVerilog IP in the FPGA
fabric performs threshold and pipelined Sobel preprocessing over
AXI-Lite-controlled image buffers.

## Current Result

```text
Board: ZedBoard
Device: XC7Z020-CLG484-1
PL clock: 142.857 MHz actual FCLK_CLK0
Samples: 8/8 PASS
FPGA threshold cycles: 786
FPGA pipelined Sobel cycles: 898
Threshold preprocessing speedup: 20.26x
Timing: +0.427 ns WNS at 142.857 MHz
```

The 142.857 MHz implementation originally failed timing at `-0.602 ns WNS`.
After adding an input-window pipeline stage to the Sobel datapath, the design
met timing at `+0.427 ns WNS` and was validated on the board.

## Architecture

```text
MNIST image
  -> ARM Cortex-A9 C app
  -> AXI-Lite writes input image/config
  -> FPGA threshold and pipelined Sobel preprocessing IP
  -> AXI-Lite reads processed image
  -> ARM fixed-point classifier
  -> UART prediction/timing output
```

Implemented classifiers:

```text
Threshold baseline:       784  -> 64 -> 10
Threshold + Sobel model:  1568 -> 96 -> 10
```

## Repository Layout

```text
rtl/                 Synthesizable SystemVerilog IP
tb/                  Questa-compatible testbenches and filelist
vitis/               Bare-metal ARM application sources
pytorch/             Training/export/golden-model scripts
scripts/             Validation helper scripts
requirements.txt     Python dependencies for the PyTorch/export scripts
generated/headers/   Quantized C model headers and golden logits
generated/test_vectors/
                     8 exported MNIST vectors, golden threshold/Sobel data
generated/model/     Metrics JSON files
hardware/            Final XSA and bitstream handoff artifacts
docs/                Results, register map, and timing-closure notes
```

This public copy intentionally excludes full Vivado/Vitis generated project
trees, simulator work directories, the raw MNIST dataset, and local reference
materials. The generated C headers and test vectors are kept so RTL simulation
and the Vitis application sources can be validated without retraining.

## Simulation

From the repository root:

```powershell
vlog -sv -f tb/filelist.f
vsim -c work.image_preprocess_axi_lite_tb +INPUT_MEM=generated/test_vectors/sample_000_input.mem +EXPECTED_MEM=generated/test_vectors/sample_000_sobel.mem +MODE=1 -do "run -all; quit"
```

Expected Sobel result:

```text
PASS: AXI wrapper matched 784 pixels.
```

## Hardware Handoff

The final hardware artifacts are:

```text
hardware/zedboard_ai_vision_pipelined_sobel.xsa
hardware/zedboard_ai_vision_pipelined_sobel.bit
```

The AXI-Lite base address used by the Vitis app is:

```text
0x40000000
```

The Vitis application expects:

```text
FPGA threshold cycles: 786
FPGA pipelined Sobel cycles: 898
```

When importing the Vitis sources into an application project, add
`generated/headers` and `generated/test_vectors` to the include path, or copy
those generated headers into the app source folder.

## Key Files

```text
rtl/image_preprocess_axi_lite.sv
rtl/image_preprocess_reg_block.sv
rtl/image_preprocess_buffered.sv
rtl/image_sobel_engine.sv
rtl/sobel_core.sv
vitis/main.c
vitis/preprocess_ip.c
vitis/classifier.c
vitis/advanced_classifier.c
```
