# Run MODE=3 implementation, bitstream generation, and XSA export for Ultra96-V1.
# This script is intended for manual execution by the user after synthesis passes.

set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir "../.."]]
set project_path [file normalize [file join $repo_root "vivado/u96_dma_vec4_vivado/u96_dma_vec4.xpr"]]
set ip_repo_dir [file normalize [file join $repo_root "vivado/ip_repo_ultra96_vec4"]]
set xsa_path [file normalize [file join $repo_root "vivado/ultra96_v1_ai_vision_dma_vec4.xsa"]]

if {![file exists $project_path]} {
    error "Missing Ultra96 MODE=3 project: $project_path."
}

open_project $project_path
set_property ip_repo_paths [list $ip_repo_dir] [current_project]
update_ip_catalog
report_ip_status

if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    error "Ultra96 MODE=3 synthesis is not complete. Run run_ultra96_v1_dma_vec4_synth.tcl first."
}

reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
puts "impl_1 status: $impl_status"
if {[string first "write_bitstream Complete" $impl_status] < 0} {
    error "Ultra96 MODE=3 implementation did not complete bitstream generation successfully."
}

open_run impl_1
report_timing_summary -file [file join $repo_root "vivado/u96_dma_vec4_impl_timing_summary.rpt"]
report_utilization -file [file join $repo_root "vivado/u96_dma_vec4_impl_utilization.rpt"]
report_drc -file [file join $repo_root "vivado/u96_dma_vec4_drc.rpt"]

write_hw_platform -fixed -include_bit -force -file $xsa_path

puts ""
puts "Ultra96-V1 MODE=3 implementation, bitstream, and XSA export complete."
puts "XSA: $xsa_path"
puts ""
