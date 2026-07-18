# Run the 1/2/4-filter out-of-context sweep on the exact Ultra96-V2 device.
# Reports are kept separate from existing V1/E-grade evidence.

set v2_script_dir [file dirname [file normalize [info script]]]
set v2_repo_root [file normalize [file join $v2_script_dir "../.."]]
set report_dir [file normalize [file join $v2_repo_root "hardware/reports/ultra96_v2/parallelism_sweep"]]
set part_name "xczu3eg-sbva484-1-i"

source [file join $v2_script_dir "run_vector_parallelism_sweep.tcl"]
