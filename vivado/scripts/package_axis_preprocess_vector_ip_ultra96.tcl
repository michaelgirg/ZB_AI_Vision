# Package the MODE=3 four-filter AXI4-Stream preprocessor for Ultra96-V1.
# This uses a separate IP repository and does not modify any stable package.

set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir "../.."]]
set ip_repo_dir [file normalize [file join $repo_root "vivado/ip_repo_ultra96_vec4"]]
set ip_root [file normalize [file join $ip_repo_dir "axis_preprocess_vector_axi_lite"]]

set part_name "xczu3eg-sbva484-1-e"
set vendor_name "local.dev"
set library_name "u96_ai_vision"
set ip_name "axis_preprocess_vector_axi_lite"
set ip_version "1.0"

puts "Repo root: $repo_root"
puts "Ultra96 IP output: $ip_root"

file mkdir $ip_repo_dir

if {[file exists $ip_root]} {
    puts "Replacing existing Ultra96 packaged IP at $ip_root"
    file delete -force $ip_root
}

create_project -in_memory axis_preprocess_vec4_u96_packager -part $part_name

set rtl_files [list \
    [file join $repo_root "rtl/sobel_core.sv"] \
    [file join $repo_root "rtl/image_sobel_engine.sv"] \
    [file join $repo_root "rtl/axis_threshold_preprocess.sv"] \
    [file join $repo_root "rtl/axis_sobel_preprocess.sv"] \
    [file join $repo_root "rtl/axis_conv3x3_parallel_preprocess.sv"] \
    [file join $repo_root "rtl/axis_conv3x3_vector4_preprocess.sv"] \
    [file join $repo_root "rtl/axis_preprocess_vector_axi_lite.sv"] \
]

foreach rtl_file $rtl_files {
    if {![file exists $rtl_file]} {
        error "Missing RTL source: $rtl_file"
    }
}

add_files -norecurse $rtl_files
set_property top axis_preprocess_vector_axi_lite [current_fileset]
update_compile_order -fileset sources_1

ipx::package_project \
    -root_dir $ip_root \
    -vendor $vendor_name \
    -library $library_name \
    -taxonomy /UserIP \
    -import_files \
    -set_current true

set core [ipx::current_core]
set_property name $ip_name $core
set_property display_name "Ultra96 AI Vision Four-Filter Vector Preprocessor" $core
set_property description "AXI4-Lite configured AXI4-Stream threshold, Sobel, single-filter convolution, and four-filter packed vector-convolution preprocessor." $core
set_property vendor $vendor_name $core
set_property library $library_name $core
set_property version $ip_version $core
set_property core_revision 2 $core
set_property supported_families {zynquplus Production} $core

ipx::infer_bus_interfaces $core

foreach busif_name {S_AXI S_AXIS M_AXIS} {
    set busif [ipx::get_bus_interfaces -quiet $busif_name -of_objects $core]
    if {[llength $busif] == 0} {
        error "Bus interface $busif_name was not inferred."
    }

    ipx::associate_bus_interfaces -busif $busif_name -clock S_AXI_ACLK $core
}

ipx::update_checksums $core
ipx::check_integrity $core
ipx::save_core $core

set_property ip_repo_paths [list $ip_repo_dir] [current_project]
update_ip_catalog

puts ""
puts "Ultra96 MODE=3 vector packaged IP complete."
puts "VLNV: $vendor_name:$library_name:$ip_name:$ip_version"
puts "IP repo: $ip_repo_dir"
puts ""

close_project
