# Zynq Edge-AI Vision Accelerator

Hardware/software co-design project for FPGA-accelerated image preprocessing and quantized AI inference. The current Ultra96-V1 architecture combines AXI4-Lite configuration, AXI4-Stream/AXI DMA transport, and four selectable preprocessing modes:

| Mode | Operation | Stream output |
| --- | --- | --- |
| 0 | Binary threshold | One 8-bit pixel |
| 1 | Sobel edge detection | One 8-bit edge value |
| 2 | Learned INT8 3x3 convolution | One 8-bit feature |
| 3 | Four learned INT8 3x3 filters in parallel | Four packed 8-bit features |

The input and output interfaces use 32-bit AXI4-Stream beats. Scalar modes place data in `TDATA[7:0]`; vector mode packs four feature channels into `TDATA[31:0]`. `TLAST` marks the final pixel of each fixed 28x28 frame.

## Results

The final Ultra96-V1 MODE=3 checkpoint achieved:

- 784/784 pixels matched against Python golden vectors
- 888-cycle selectable-top frame latency under no backpressure
- 4/4 UVM tests passing with zero UVM errors, fatals, or assertion failures
- 100% targeted stream and control functional coverage
- post-implementation WNS `+4.413 ns`, TNS `0`, and zero failing endpoints
- 10,359 LUTs, 11,903 registers, 3 BRAM tiles, and 45 DSP48E2 blocks
- zero DRC errors or critical warnings

The 45 DSPs comprise nine multipliers for MODE=2 and 36 parallel multipliers for the four-filter MODE=3 datapath. See [results.md](docs/results.md) and [ppa_comparison.md](docs/ppa_comparison.md) for the full verification and implementation record.

## Repository Layout

```text
rtl/                 Synthesizable SystemVerilog datapaths and wrappers
tb/                  Directed, self-checking RTL testbenches
verif/               BFM/SVA tests plus AXI-stream mini-UVM environments
pytorch/             Training, quantization, export, and golden models
generated/           Exported weights, metadata, and deterministic test vectors
software/zedboard/    Bare-metal C classifier and register driver checkpoint
vivado/scripts/       Portable Ultra96-V1 IP packaging and build Tcl
hardware/reports/     Selected timing, utilization, hierarchy, and DRC reports
docs/                 Architecture, register map, timing, and verification notes
```

Generated Vivado/Vitis projects, XSA files containing local IP metadata, raw MNIST downloads, Python environments, simulator databases, and machine-specific files are intentionally excluded. The scripts below recreate the hardware checkpoint with the neutral `local.dev` IP vendor identifier.

## Python Golden Pipeline

Create an environment and install dependencies:

```bash
python -m venv .venv
python -m pip install -r requirements.txt
```

The checked-in `generated/` artifacts make RTL verification reproducible without downloading or retraining MNIST. The scripts in `pytorch/` document the training and export path for the quantized classifiers and learned convolution kernels.

## Questa Verification

Run commands from the repository root. A basic directed compile is:

```tcl
vlib work
vlog -sv -f tb/filelist.f
vsim -c work.axis_preprocess_vector_axi_lite_tb -do "run -all; quit -f"
```

For the final AXI-stream UVM regression on a Questa installation with UVM enabled:

```bash
bash verif/uvm_axis/run_server_regression.sh
```

The regression covers all four modes, randomized backpressure, reset/control behavior, output scoreboarding, `TLAST`, and functional coverage. Details are in [verification_plan.md](docs/verification_plan.md).

## Rebuild The Ultra96 Checkpoint

Vivado 2025.2 and the Avnet Ultra96-V1 board definition are required. If the board files are not in Vivado's normal user store, set `XILINX_BOARD_REPO` to the directory containing the board definitions.

```powershell
vivado -mode batch -source .\vivado\scripts\check_ultra96_v1_board.tcl
vivado -mode batch -source .\vivado\scripts\package_axis_preprocess_vector_ip_ultra96.tcl
vivado -mode batch -source .\vivado\scripts\create_ultra96_v1_dma_vec4_project.tcl
vivado -mode batch -source .\vivado\scripts\run_ultra96_v1_dma_vec4_synth.tcl
vivado -mode batch -source .\vivado\scripts\run_ultra96_v1_dma_vec4_bitstream_export.tcl
```

The creation script refuses to overwrite an existing generated project. Delete or rename that generated project directory deliberately before rebuilding.

## Architecture Notes

- [AXI4-Stream and DMA architecture](docs/axi_stream_dma_architecture.md)
- [Learned convolution architecture](docs/learned_conv_architecture.md)
- [Convolution latency audit](docs/convolution_latency_performance_audit.md)
- [AXI-Lite register map](docs/register_map.md)
- [Timing closure](docs/timing_closure.md)
