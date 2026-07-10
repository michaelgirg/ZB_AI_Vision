# Create the separate Ultra96-V1 AXI DMA + four-filter vector project.

set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir "../.."]]
set project_name "u96_dma_vec4"
set project_dir [file normalize [file join $repo_root "vivado/u96_dma_vec4_vivado"]]
set bd_name "u96v4bd"
set ip_repo_dir [file normalize [file join $repo_root "vivado/ip_repo_ultra96_vec4"]]

set part_name "xczu3eg-sbva484-1-e"
set board_repo_path ""
if {[info exists ::env(XILINX_BOARD_REPO)]} {
    set board_repo_path [file normalize $::env(XILINX_BOARD_REPO)]
} elseif {[info exists ::env(APPDATA)]} {
    set board_repo_path [file normalize [file join $::env(APPDATA) \
        "Xilinx/Vivado/2025.2/xhub/board_store/xilinx_board_store/XilinxBoardStore/Vivado/2025.2/boards"]]
}
set preproc_vlnv "local.dev:u96_ai_vision:axis_preprocess_vector_axi_lite:1.0"

proc find_ultra96_v1_board_part {} {
    set available [get_board_parts -quiet *ultra96*]
    set preferred [list \
        "em.avnet.com:ultra96v1:part0:1.2" \
        "avnet.com:ultra96v1:part0:1.2" \
        "em.avnet.com:ultra96:part0:1.2" \
        "avnet.com:ultra96:part0:1.2" \
    ]

    foreach candidate $preferred {
        if {[lsearch -exact $available $candidate] >= 0} {
            return $candidate
        }
    }

    foreach candidate $available {
        if {[string match "*ultra96v1*" [string tolower $candidate]]} {
            return $candidate
        }
    }

    foreach candidate $available {
        set name [string tolower $candidate]
        if {[string match "*ultra96:*" $name] && ![string match "*ultra96v2*" $name]} {
            return $candidate
        }
    }

    return ""
}

puts "Repo root: $repo_root"
puts "Ultra96-V1 MODE=3 DMA project: $project_dir"

if {[file exists [file join $project_dir "$project_name.xpr"]]} {
    error "Project already exists: $project_dir. This script will not overwrite it."
}

if {![file exists [file join $ip_repo_dir "axis_preprocess_vector_axi_lite/component.xml"]]} {
    puts "Ultra96 MODE=3 packaged IP was not found. Packaging it now."
    source [file join $script_dir "package_axis_preprocess_vector_ip_ultra96.tcl"]
}

if {$board_repo_path ne "" && [file exists $board_repo_path]} {
    set_param board.repoPaths [list $board_repo_path]
}

set board_part [find_ultra96_v1_board_part]
if {$board_part eq ""} {
    error "No Ultra96-V1 board definition is installed. Run check_ultra96_v1_board.tcl, then install the Avnet Ultra96 board from Vivado Store."
}

puts "Using board part: $board_part"

create_project $project_name $project_dir -part $part_name
set_property board_part $board_part [current_project]
set_property ip_repo_paths [list $ip_repo_dir] [current_project]
update_ip_catalog

if {[llength [get_ipdefs -all $preproc_vlnv]] == 0} {
    error "Could not find packaged IP VLNV: $preproc_vlnv"
}

create_bd_design $bd_name

create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:* ps
apply_bd_automation \
    -rule xilinx.com:bd_rule:zynq_ultra_ps_e \
    -config {apply_board_preset "1"} \
    [get_bd_cells ps]

set_property -dict [list \
    CONFIG.PSU__USE__M_AXI_GP0 {1} \
    CONFIG.PSU__USE__M_AXI_GP1 {0} \
    CONFIG.PSU__USE__S_AXI_GP2 {1} \
    CONFIG.PSU__FPGA_PL0_ENABLE {1} \
    CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ {100} \
    CONFIG.PSU__USE__FABRIC__RST {1} \
    CONFIG.PSU__NUM_FABRIC_RESETS {1} \
] [get_bd_cells ps]

if {[get_property CONFIG.PSU__USE__M_AXI_GP1 [get_bd_cells ps]] != 0} {
    error "Unused M_AXI_HPM1_FPD remained enabled after PS configuration."
}

create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:* rst
set_property CONFIG.C_EXT_RESET_HIGH {0} [get_bd_cells rst]

create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:* locked
set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL {1}] [get_bd_cells locked]

create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:* dma
set_property -dict [list \
    CONFIG.c_include_sg {0} \
    CONFIG.c_include_mm2s {1} \
    CONFIG.c_include_s2mm {1} \
    CONFIG.c_m_axi_mm2s_data_width {32} \
    CONFIG.c_m_axi_s2mm_data_width {32} \
    CONFIG.c_s_axis_s2mm_tdata_width {32} \
] [get_bd_cells dma]

create_bd_cell -type ip -vlnv $preproc_vlnv pre

create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:* sc_ctrl
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {2}] [get_bd_cells sc_ctrl]

create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:* sc_hp
set_property -dict [list CONFIG.NUM_SI {2} CONFIG.NUM_MI {1}] [get_bd_cells sc_hp]

connect_bd_net [get_bd_pins ps/pl_clk0] [get_bd_pins ps/maxihpm0_fpd_aclk]
connect_bd_net [get_bd_pins ps/pl_clk0] [get_bd_pins ps/saxihp0_fpd_aclk]
connect_bd_net [get_bd_pins ps/pl_clk0] [get_bd_pins rst/slowest_sync_clk]
connect_bd_net [get_bd_pins ps/pl_resetn0] [get_bd_pins rst/ext_reset_in]
connect_bd_net [get_bd_pins locked/dout] [get_bd_pins rst/dcm_locked]

connect_bd_net [get_bd_pins ps/pl_clk0] [get_bd_pins sc_ctrl/aclk]
connect_bd_net [get_bd_pins ps/pl_clk0] [get_bd_pins sc_hp/aclk]
connect_bd_net [get_bd_pins rst/peripheral_aresetn] [get_bd_pins sc_ctrl/aresetn]
connect_bd_net [get_bd_pins rst/peripheral_aresetn] [get_bd_pins sc_hp/aresetn]

connect_bd_net [get_bd_pins ps/pl_clk0] [get_bd_pins dma/s_axi_lite_aclk]
connect_bd_net [get_bd_pins ps/pl_clk0] [get_bd_pins dma/m_axi_mm2s_aclk]
connect_bd_net [get_bd_pins ps/pl_clk0] [get_bd_pins dma/m_axi_s2mm_aclk]
connect_bd_net [get_bd_pins rst/peripheral_aresetn] [get_bd_pins dma/axi_resetn]

connect_bd_net [get_bd_pins ps/pl_clk0] [get_bd_pins pre/S_AXI_ACLK]
connect_bd_net [get_bd_pins rst/peripheral_aresetn] [get_bd_pins pre/S_AXI_ARESETN]

connect_bd_intf_net [get_bd_intf_pins ps/M_AXI_HPM0_FPD] [get_bd_intf_pins sc_ctrl/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins sc_ctrl/M00_AXI] [get_bd_intf_pins dma/S_AXI_LITE]
connect_bd_intf_net [get_bd_intf_pins sc_ctrl/M01_AXI] [get_bd_intf_pins pre/S_AXI]

connect_bd_intf_net [get_bd_intf_pins dma/M_AXI_MM2S] [get_bd_intf_pins sc_hp/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins dma/M_AXI_S2MM] [get_bd_intf_pins sc_hp/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins sc_hp/M00_AXI] [get_bd_intf_pins ps/S_AXI_HP0_FPD]

connect_bd_intf_net [get_bd_intf_pins dma/M_AXIS_MM2S] [get_bd_intf_pins pre/S_AXIS]
connect_bd_intf_net [get_bd_intf_pins pre/M_AXIS] [get_bd_intf_pins dma/S_AXIS_S2MM]

assign_bd_address
validate_bd_design
save_bd_design

set wrapper_path [make_wrapper -files [get_files [file join $project_dir "$project_name.srcs/sources_1/bd/$bd_name/$bd_name.bd"]] -top]
add_files -norecurse $wrapper_path
set_property top ${bd_name}_wrapper [current_fileset]
update_compile_order -fileset sources_1

puts ""
puts "Ultra96-V1 MODE=3 DMA block design created."
puts "Project: [file join $project_dir "$project_name.xpr"]"
puts "Board part: $board_part"
puts "Processor target for the first Vitis application: psu_cortexa53_0"
puts ""
