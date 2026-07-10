# Verification Coverage Plan

## Scope

This plan covers the AXI-Lite controlled preprocessing IP used by the ZedBoard
AI Vision pipeline.

## Code Coverage

Run RTL with Questa code coverage enabled:

```bash
vlog -sv -assertdebug -cover bcesft -mfcu -cuname preprocess_verif_cu -f verif/filelist.f
```

Coverage goals:

| Area | Goal |
| --- | ---: |
| Statement coverage | 90%+ |
| Branch coverage | 85%+ |
| Condition/expression coverage | Explain misses |
| FSM coverage | All reachable states |
| Toggle coverage | Report only; do not force meaningless high-bit toggles |

## Functional Coverage

Implemented covergroups:

| Covergroup | Intent |
| --- | --- |
| `axi_lite_protocol_coverage.axi_cg` | AXI read/write handshakes, response stalls, register address access |
| `preprocess_reg_block_coverage.reg_cg` | mode writes, threshold writes, start/done/clear, busy-time writes |

Coverage goals:

| Feature | Bins |
| --- | --- |
| Processing mode | threshold, Sobel |
| Invalid mode writes | values 2 and 3 |
| Threshold writes | 0, 1, 127, 128, 254, 255 |
| Control writes | start, clear_done, start+clear |
| Busy-time writes | input write, threshold write, mode write |
| AXI response stalls | B channel stall, R channel stall |
| Register accesses | status, constants, cycles, mode, image buffers |

## Assertions

Implemented SVA checks:

| Assertion Area | Checks |
| --- | --- |
| Reset | response channels clear, register defaults restore |
| AXI-Lite | response hold under backpressure, OKAY responses, stable valid payloads |
| Sequencing | done latches, clear_done clears, cycle count nonzero |
| Safety | input writes blocked while busy, busy-time config writes ignored |
| Invalid config | invalid mode values clamp to threshold mode |

## Current Tests

| Test | Purpose |
| --- | --- |
| `test_axi_lite_directed_verif` mode 0 | threshold path, register constants, busy writes, clear_done |
| `test_axi_lite_directed_verif` mode 1 | Sobel path, register constants, busy writes, clear_done |
| `test_axi_lite_control_coverage` | threshold boundary bins, invalid modes, start+clear control write |

## Planned Tests

| Test | Purpose |
| --- | --- |
| `test_random_axi_reads_writes` | randomized legal register ordering and response stalls |
| `test_random_images` | generated random image vectors checked against Python model |
| `test_reset_mid_transaction` | reset during AXI and active preprocessing |
| `test_threshold_sweep` | boundary thresholds 0, 1, 127, 128, 254, 255 |
