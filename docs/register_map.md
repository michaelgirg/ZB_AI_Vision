# Preprocessing IP Register Map

This is the planned control surface for the ZedBoard PS-to-PL wrapper. The
current RTL already proves the datapath with simple host-style ports; this map
is the target for the later AXI-Lite wrapper.

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
| `0x2C` | `MODE` | RW | `0` = threshold, `1` = Sobel, `2` = single learned conv, `3` = four-filter vector conv |

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

## AXI DMA Stream Top Additions

The DMA-oriented top `axis_preprocess_axi_lite` does not use the
`INPUT_ADDR`/`INPUT_WDATA`/`OUTPUT_ADDR` buffer registers. Pixels move through
AXI DMA on `S_AXIS` and `M_AXIS`.

It reuses the common control/status registers and adds learned convolution
configuration registers:

| Offset | Name | Access | Description |
| --- | --- | --- | --- |
| `0x30` | `CONV_K00` | RW | signed INT8 kernel coefficient |
| `0x34` | `CONV_K01` | RW | signed INT8 kernel coefficient |
| `0x38` | `CONV_K02` | RW | signed INT8 kernel coefficient |
| `0x3C` | `CONV_K10` | RW | signed INT8 kernel coefficient |
| `0x40` | `CONV_K11` | RW | signed INT8 kernel coefficient |
| `0x44` | `CONV_K12` | RW | signed INT8 kernel coefficient |
| `0x48` | `CONV_K20` | RW | signed INT8 kernel coefficient |
| `0x4C` | `CONV_K21` | RW | signed INT8 kernel coefficient |
| `0x50` | `CONV_K22` | RW | signed INT8 kernel coefficient |
| `0x54` | `CONV_BIAS` | RW | signed INT32 bias |
| `0x58` | `CONV_SHIFT` | RW | arithmetic right shift amount, bits `[4:0]` |
| `0x5C` | `CONV_RELU_EN` | RW | bit 0 enables ReLU after shifting |
| `0x60` | `VECTOR_CFG_INDEX` | RW | bits `[5:4]` select filter 0-3; bits `[3:0]` select entry |
| `0x64` | `VECTOR_CFG_DATA` | RW | shadow-bank data/readback for the selected vector entry |
| `0x68` | `VECTOR_CFG_COMMIT` | WO | bit 0 atomically commits all shadow parameters while idle |
| `0x6C` | `VECTOR_CFG_VERSION` | RO | increments after each accepted vector commit |

For MODE=3, vector entries 0-8 are signed INT8 kernel taps, entry 9 is signed
INT32 bias, and entry 10 stores shift in bits `[4:0]` plus ReLU enable in bit 8.
Start snapshots the committed bank into active frame configuration. Shadow
writes and rejected busy-time commits cannot corrupt an in-flight packet.

The DMA top latches threshold, mode, and convolution configuration when
`CTRL.start` is accepted. Writes during an active frame are ignored by the
register file so the current DMA packet cannot be corrupted mid-operation.

## Notes For AXI-Lite Wrapper

- `CTRL.start` should act like a one-cycle pulse internally, even if software
  writes a `1`.
- `STATUS.done` should stay high until software writes `CTRL.clear_done`.
- Buffer reads may be registered, so software should treat `OUTPUT_RDATA` as
  valid one access after setting `OUTPUT_ADDR` unless the wrapper later adds a
  stronger handshake.
- For the MVP, `IMAGE_WIDTH`, `IMAGE_HEIGHT`, and `PIXELS_PER_CYCLE` remain
  compile-time parameters. Runtime-configurable image sizes can be added later
  once the fixed 28x28 path is working on hardware.
