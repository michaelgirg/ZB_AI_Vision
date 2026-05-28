# Preprocessing IP Register Map

This is the implemented control surface for the ZedBoard PS-to-PL wrapper. The
top-level AXI-Lite slave is `rtl/image_preprocess_axi_lite.sv`, which wraps the
software-visible register block in `rtl/image_preprocess_reg_block.sv`.

## Design Intent

- Keep the low-latency threshold engine separate from bus protocol logic.
- Use parameterized image size and pixels-per-cycle in RTL.
- Expose cycle count so ARM software can compare FPGA preprocessing against
  ARM-only preprocessing.
- Use simple buffer access first; move to AXI DMA only after the MVP works.

## Register Table

| Offset | Name | Access | Description |
| --- | --- | --- | --- |
| `0x00` | `CTRL` | RW | bit 0 = start pulse, bit 1 = clear done |
| `0x04` | `STATUS` | RO | bit 0 = busy, bit 1 = done |
| `0x08` | `THRESHOLD` | RW | 8-bit threshold value, default `128` |
| `0x0C` | `IMAGE_PIXELS` | RO | Total pixels compiled into the IP |
| `0x10` | `PIXELS_PER_CYCLE` | RO | Parallel lanes compiled into the IP |
| `0x14` | `PROCESSING_CYCLES` | RO | Engine cycles from start to done |
| `0x18` | `INPUT_ADDR` | RW | Input buffer beat address |
| `0x1C` | `INPUT_WDATA` | WO | Input buffer write data beat |
| `0x20` | `INPUT_WMASK` | WO | Input buffer lane write mask |
| `0x24` | `OUTPUT_ADDR` | RW | Output buffer beat address |
| `0x28` | `OUTPUT_RDATA` | RO | Output buffer read data beat |
| `0x2C` | `MODE` | RW | `0` = threshold, `1` = Sobel |

## Expected Software Flow

1. Write all input image beats through `INPUT_ADDR`, `INPUT_WDATA`, and
   `INPUT_WMASK`.
2. Write `MODE`.
3. Write `THRESHOLD` when using threshold mode.
4. Pulse `CTRL.start`.
5. Poll `STATUS.done`.
6. Read `PROCESSING_CYCLES`.
7. Read all output image beats through `OUTPUT_ADDR` and `OUTPUT_RDATA`.

The first Vitis driver for this flow lives in:

```text
vitis/preprocess_ip.c
vitis/preprocess_ip.h
```

That driver currently assumes one pixel per beat (`PIXELS_PER_CYCLE = 1`).
The Vitis app checks this register before running. Sobel mode also currently
requires `PIXELS_PER_CYCLE = 1`.

## AXI-Lite Wrapper Notes

- `CTRL.start` acts like a one-cycle pulse internally, even if software writes a
  `1`.
- `STATUS.done` stays high until software writes `CTRL.clear_done`.
- Buffer reads may be registered, so software should treat `OUTPUT_RDATA` as
  valid one access after setting `OUTPUT_ADDR` unless the wrapper later adds a
  stronger handshake.
- For the MVP, `IMAGE_WIDTH`, `IMAGE_HEIGHT`, and `PIXELS_PER_CYCLE` remain
  compile-time parameters. Runtime-configurable image sizes can be added later
  once the fixed 28x28 path is working on hardware.
