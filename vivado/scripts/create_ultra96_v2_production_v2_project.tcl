# Create a separate Ultra96-V2 DMA project for the production-v2 dual-clock
# IP. The V1 implementation is shared, while V2 keeps a distinct project,
# block-design name, board selector, reports, and eventual XSA.

set v2_script_dir [file dirname [file normalize [info script]]]
set v2_repo_root [file normalize [file join $v2_script_dir "../.."]]

set project_name "u96v2_production_v2"
set project_dir [file normalize [file join $v2_repo_root "vivado/u96v2_production_v2_vivado"]]
set bd_name "u96v2prod"
# The installed Avnet Ultra96-V2 board definition identifies the industrial
# ZU3EG part. Keep this override V2-only; V1 remains -1-e.
set part_name "xczu3eg-sbva484-1-i"
set ultra96_board_variant "v2"
set ultra96_board_label "Ultra96-V2"
set ultra96_board_check_script "check_ultra96_v2_board.tcl"
set ultra96_board_preferred [list \
    "em.avnet.com:ultra96v2:part0:1.2" \
    "avnet.com:ultra96v2:part0:1.2" \
    "em.avnet.com:ultra96v2:part0:1.1" \
    "avnet.com:ultra96v2:part0:1.1" \
    "em.avnet.com:ultra96v2:part0:1.0" \
    "avnet.com:ultra96v2:part0:1.0" \
]

source [file join $v2_script_dir "create_ultra96_v1_production_v2_project.tcl"]
