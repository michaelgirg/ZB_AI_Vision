# Synthesize the Ultra96-V2 production-v2 project. The shared V1 synthesis
# implementation is parameterized so V2 retains an isolated project and report
# tree without duplicating the checked flow.

set v2_script_dir [file dirname [file normalize [info script]]]
set v2_repo_root [file normalize [file join $v2_script_dir "../.."]]

set project_path [file normalize [file join $v2_repo_root "vivado/u96v2_production_v2_vivado/u96v2_production_v2.xpr"]]
set report_dir [file normalize [file join $v2_repo_root "hardware/reports/ultra96_v2/production_v2/synth"]]
set ultra96_board_label "Ultra96-V2"
set ultra96_create_script "create_ultra96_v2_production_v2_project.tcl"

source [file join $v2_script_dir "run_ultra96_v1_production_v2_synth.tcl"]
