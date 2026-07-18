# Ultra96-V2 Build Flow

The production hardware flow targets the Ultra96-V2 board and the `xczu3eg-sbva484-1-i` device.

## Board setup

Install the Ultra96-V2 board definition in Vivado, or point `ULTRA96_BOARD_REPO` at the board-store directory containing the board files. The repository includes `vivado/scripts/check_ultra96_v2_board.tcl` for a quick board-part check.

## Vivado flow

From the repository root, run the scripts with Vivado in batch mode:

```text
vivado -mode batch -source vivado/scripts/check_ultra96_v2_board.tcl
vivado -mode batch -source vivado/scripts/run_ultra96_v2_parallelism_sweep.tcl
vivado -mode batch -source vivado/scripts/create_ultra96_v2_production_v2_project.tcl
vivado -mode batch -source vivado/scripts/run_ultra96_v2_production_v2_synth.tcl
vivado -mode batch -source vivado/scripts/run_ultra96_v2_production_v2_implementation.tcl
```

On Windows, `scripts/run_ultra96_v2_local_vivado.ps1` wraps these stages. Pass `-VivadoPath` when Vivado is not on `PATH`, and pass `-BoardRepo` when the board definition is stored outside Vivado's default board store.

Generated Vivado projects, logs, reports, bitstreams, and XSA files are intentionally excluded from source control. Release binaries are distributed separately with the matching SHA256 manifest.
