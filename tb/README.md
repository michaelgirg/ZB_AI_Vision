# Testbenches

Current testbench:

```text
image_preprocess_tb.sv
sobel_core_tb.sv
image_preprocess_engine_tb.sv
image_sobel_engine_tb.sv
image_preprocess_buffered_tb.sv
image_preprocess_reg_block_tb.sv
image_preprocess_axi_lite_tb.sv
```

`image_preprocess_tb.sv` verifies `rtl/threshold_core.sv` against Python-generated `.mem` files.

`sobel_core_tb.sv` verifies `rtl/sobel_core.sv` against Python-generated
Sobel `.mem` files.

`image_preprocess_engine_tb.sv` verifies `rtl/image_preprocess_engine.sv` against the same golden files, but at full-image granularity.

`image_sobel_engine_tb.sv` verifies `rtl/image_sobel_engine.sv` against
Python-generated Sobel `.mem` files at full-image granularity.

`image_preprocess_buffered_tb.sv` verifies `rtl/image_preprocess_buffered.sv`, including host-style input-buffer writes and output-buffer reads.

`image_preprocess_reg_block_tb.sv` verifies `rtl/image_preprocess_reg_block.sv`
using the planned software-visible register flow.

`image_preprocess_axi_lite_tb.sv` verifies `rtl/image_preprocess_axi_lite.sv`
through AXI4-Lite read/write transactions.

Default vectors:

```text
generated/test_vectors/sample_000_input.mem
generated/test_vectors/sample_000_threshold.mem
generated/test_vectors/sample_000_sobel.mem
```

The testbench supports plusargs:

```text
+INPUT_MEM=generated/test_vectors/sample_001_input.mem
+EXPECTED_MEM=generated/test_vectors/sample_001_threshold.mem
+MODE=0
```

For Sobel, point `EXPECTED_MEM` at the Sobel golden output:

```text
+INPUT_MEM=generated/test_vectors/sample_001_input.mem
+EXPECTED_MEM=generated/test_vectors/sample_001_sobel.mem
+MODE=1
```

Expected result:

```text
PASS: threshold output matched 784 pixels.
```

Sobel expected result:

```text
PASS: Sobel core matched 784 pixels with 3-cycle datapath latency.
```

Sobel engine expected result:

```text
PASS: Sobel engine matched 784 pixels in 898 cycles.
```

For Questa commands, see `docs/questa_run.md`.
