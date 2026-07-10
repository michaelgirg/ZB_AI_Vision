# Report Ultra96 board definitions visible to Vivado without creating a project.

set board_repo_path ""
if {[info exists ::env(XILINX_BOARD_REPO)]} {
    set board_repo_path [file normalize $::env(XILINX_BOARD_REPO)]
} elseif {[info exists ::env(APPDATA)]} {
    set board_repo_path [file normalize [file join $::env(APPDATA) \
        "Xilinx/Vivado/2025.2/xhub/board_store/xilinx_board_store/XilinxBoardStore/Vivado/2025.2/boards"]]
}

if {$board_repo_path ne "" && [file exists $board_repo_path]} {
    set_param board.repoPaths [list $board_repo_path]
}

set matches [get_board_parts -quiet *ultra96*]

puts ""
puts "Ultra96 board parts visible to Vivado:"
if {[llength $matches] == 0} {
    puts "  NONE"
    puts "Install the Avnet Ultra96 board definition from Tools > Vivado Store > Boards."
    exit 1
}

foreach match $matches {
    puts "  $match"
}

set v1_matches [list]
foreach match $matches {
    set name [string tolower $match]
    if {[string match "*ultra96v1*" $name] ||
        ([string match "*ultra96:*" $name] && ![string match "*ultra96v2*" $name])} {
        lappend v1_matches $match
    }
}

if {[llength $v1_matches] == 0} {
    puts ""
    puts "ERROR: Ultra96 definitions were found, but none clearly target Ultra96-V1."
    exit 1
}

puts ""
puts "Ultra96-V1 candidate: [lindex $v1_matches end]"
exit 0
