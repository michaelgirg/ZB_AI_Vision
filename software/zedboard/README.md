# Vitis ARM Classifier

This folder contains the fixed-point classifier and preprocessing IP driver
that the ARM Cortex-A9 will use after the FPGA preprocessing block produces a
thresholded or Sobel image.

## Files

```text
classifier.c
classifier.h
advanced_classifier.c
advanced_classifier.h
main.c
preprocess_ip.c
preprocess_ip.h
test_classifier_host.c
```

`classifier.c` consumes the generated quantized model header:

```text
generated/headers/model_weights_quantized.h
```

`advanced_classifier.c` consumes the generated threshold+Sobel model header:

```text
generated/headers/model_weights_threshold_sobel_quantized.h
```

The host test also consumes:

```text
generated/headers/model_quantized_golden.h
generated/test_vectors/sample_000_image_data.h
...
generated/test_vectors/sample_007_image_data.h
```

## Expected Build Shape

On a machine with a C compiler available, compile from the project root with
include paths for the generated headers:

```powershell
gcc -std=c99 -Wall -Wextra -Isoftware/zedboard -Igenerated/headers -Igenerated/test_vectors software/zedboard/classifier.c software/zedboard/test_classifier_host.c -o classifier_host_test
generated\classifier_host_test.exe
```

The expected result is that all 8 exported samples pass with logits matching
`model_quantized_golden.h`.

## Vitis Use

For the bare-metal ZedBoard app, include these source files:

```text
software/zedboard/main.c
software/zedboard/classifier.c
software/zedboard/advanced_classifier.c
software/zedboard/preprocess_ip.c
```

Add these include paths:

```text
software/zedboard
generated/headers
generated/test_vectors
```

Set `PREPROCESS_IP_BASEADDR` to the AXI-Lite base address Vivado assigns to the
custom preprocessing IP. The current ZedBoard hardware build uses
`0x40000000`.

The classifier entry point is:

```c
classifier_predict_from_thresholded(fpga_output_image, logits);
```

The function returns the predicted digit and fills the `int32_t logits[10]`
array for validation or UART printing.

The upgraded classifier entry point is:

```c
advanced_classifier_predict_from_threshold_sobel(
    fpga_threshold_image,
    fpga_sobel_image,
    logits
);
```

That path deploys the `1568 -> 96 -> 10` quantized PyTorch model on ARM.

The current board app loops over all 8 exported samples and validates each
sample against Python golden threshold images, Sobel images, baseline logits,
and advanced threshold+Sobel logits.

## Timing Output

`main.c` measures ARM-only threshold preprocessing with `XTime_GetTime()`,
checks FPGA threshold mode, checks FPGA Sobel mode, times both ARM classifier
paths, and compares ARM threshold cycles against the FPGA threshold cycle
counter:

```text
Validation Summary
Sample    Label  Threshold  Advanced  Result
sample_000  7      7          7         PASS
...

Timing Summary
Samples passed: 8/8
Avg ARM threshold preprocess cycles: XXXX
Avg FPGA threshold preprocess cycles: 786
Avg FPGA Sobel preprocess cycles: 898
Threshold preprocessing speedup: Z.ZZx
Avg threshold model inference cycles: XXXX
Avg advanced model inference cycles: YYYY
Advanced inference ratio: Z.ZZx threshold model
```

Older pre-pipeline bitstreams reported 897 Sobel cycles. The current
150 MHz-oriented RTL adds one Sobel pipeline stage, so the expected hardware
counter is 898 cycles after regenerating the bitstream.

On Zynq, the global timer increments at half the CPU clock, so the app reports
ARM CPU cycles as:

```text
timer_counts * 2
```

The printed ARM threshold benchmark is small enough for 32-bit UART printing in
this MVP.

## Hardware Compatibility

The app checks the hardware cycle counters:

```text
expected threshold cycles: 786
expected pipelined Sobel cycles: 898
```

If the board accidentally runs the older pre-pipeline bitstream, the Sobel cycle
check should fail because that design reports 897 cycles.
