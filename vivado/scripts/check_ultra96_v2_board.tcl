# Report Ultra96-V2 board definitions visible to Vivado without creating a
# project. The shared checker also honors ULTRA96_BOARD_REPO when supplied.

set ultra96_board_variant "v2"
set ultra96_board_label "Ultra96-V2"
set script_dir [file dirname [file normalize [info script]]]
source [file join $script_dir "check_ultra96_v1_board.tcl"]
