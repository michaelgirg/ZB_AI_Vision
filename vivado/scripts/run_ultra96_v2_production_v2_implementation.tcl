# Implement the isolated Ultra96-V2 production-v2 project after V2 synthesis
# evidence is reviewed. Its bitstream and XSA names cannot collide with V1.

set v2_script_dir [file dirname [file normalize [info script]]]
set v2_repo_root [file normalize [file join $v2_script_dir "../.."]]

set project_path [file normalize [file join $v2_repo_root "vivado/u96v2_production_v2_vivado/u96v2_production_v2.xpr"]]
set report_dir [file normalize [file join $v2_repo_root "hardware/reports/ultra96_v2/production_v2/impl"]]
set xsa_path [file normalize [file join $v2_repo_root "vivado/ultra96_v2_ai_vision_production_v2.xsa"]]
set ultra96_board_label "Ultra96-V2"

source [file join $v2_script_dir "run_ultra96_v1_production_v2_implementation.tcl"]
