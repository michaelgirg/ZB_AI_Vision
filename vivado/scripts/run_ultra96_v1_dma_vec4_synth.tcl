# Run synthesis for the separate Ultra96-V1 DMA + MODE=3 vector project.
# This script is intended for manual execution by the user.

set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir "../.."]]
set project_path [file normalize [file join $repo_root "vivado/u96_dma_vec4_vivado/u96_dma_vec4.xpr"]]
set ip_repo_dir [file normalize [file join $repo_root "vivado/ip_repo_ultra96_vec4"]]

if {![file exists $project_path]} {
    error "Missing Ultra96 MODE=3 project: $project_path. Run create_ultra96_v1_dma_vec4_project.tcl first."
}

open_project $project_path
set_property ip_repo_paths [list $ip_repo_dir] [current_project]
update_ip_catalog
report_ip_status

set axis_ip [get_ips -quiet "*axis_preprocess*"]
if {[llength $axis_ip] != 0} {
    upgrade_ip $axis_ip
}

set bd_files [get_files -quiet "*.bd"]
if {[llength $bd_files] != 0} {
    generate_target all $bd_files
}

update_compile_order -fileset sources_1

set top_module [get_property top [get_filesets sources_1]]
if {$top_module eq ""} {
    error "No synthesis top is set. The block-design creation did not finish; remove only vivado/u96_dma_vec4_vivado and recreate it."
}

puts "Synthesis top: $top_module"
reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1

set synth_status [get_property STATUS [get_runs synth_1]]
puts "synth_1 status: $synth_status"
if {[string first "synth_design Complete" $synth_status] < 0} {
    error "Ultra96 MODE=3 synth_1 did not complete successfully."
}

open_run synth_1
report_timing_summary -file [file join $repo_root "vivado/u96_dma_vec4_synth_timing_summary.rpt"]
report_utilization -file [file join $repo_root "vivado/u96_dma_vec4_synth_utilization.rpt"]
report_utilization -hierarchical -hierarchical_depth 5 -file [file join $repo_root "vivado/u96_dma_vec4_synth_hierarchical_utilization.rpt"]

puts ""
puts "Ultra96-V1 MODE=3 synthesis complete."
puts "Review u96_dma_vec4_synth_timing_summary.rpt before implementation."
puts ""
