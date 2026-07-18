#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

rm -rf work transcript vsim.wlf
rm -f vector_*.ucdb vector_*.log vector_coverage_report.txt

vlib work
vlog -sv -cover bcesft -f verif/uvm_axis/filelist.f

run_uvm_test() {
    local test_name="$1"
    local output_name="$2"
    local pass_marker="${3:-PASS: matched 784 packed vector outputs}"
    local extra_args="${4:-}"

    vsim -c -coverage -assertdebug -onfinish stop \
        -sv_seed 24601 \
        work.vector_stream_uvm_top \
        "+UVM_TESTNAME=${test_name}" \
        +UVM_VERBOSITY=UVM_MEDIUM \
        +INPUT_MEM=generated/test_vectors/sample_000_input.mem \
        +EXPECTED_MEM=generated/test_vectors/sample_000_conv4.mem \
        ${extra_args} \
        -l "vector_${output_name}.log" \
        -do "run -all; coverage save vector_${output_name}.ucdb; quit -f"

    grep -Eq "UVM_ERROR[[:space:]]*:[[:space:]]*0" "vector_${output_name}.log"
    grep -Eq "UVM_FATAL[[:space:]]*:[[:space:]]*0" "vector_${output_name}.log"
    grep -q "$pass_marker" "vector_${output_name}.log"
    if grep -Eq "Errors:[[:space:]]*[1-9][0-9]*" "vector_${output_name}.log"; then
        echo "Simulator error detected in vector_${output_name}.log" >&2
        exit 1
    fi
    if grep -Eiq "assertion[^[:space:]]*.*(failed|failure|violation)|\*\* Error:.*assert" \
        "vector_${output_name}.log"; then
        echo "Assertion failure detected in vector_${output_name}.log" >&2
        exit 1
    fi
}

run_uvm_test vector4_stream_test directed
run_uvm_test vector4_backpressure_test backpressure
run_uvm_test vector4_busy_write_test busy_write
run_uvm_test vector4_saturation_test saturation
run_uvm_test vector4_diagnostics_test diagnostics "PASS: production counters, W1C diagnostics, access errors, and IRQ completed"
run_uvm_test vector4_wstrb_test wstrb "PASS: AXI4-Lite WSTRB preservation checks completed"
run_uvm_test vector4_axi_protocol_test axi_protocol "PASS: randomized AXI4-Lite ordering/response checks completed"
run_uvm_test vector4_ral_test ral "PASS: UVM RAL reset/readback/bit-bash checks completed"
run_uvm_test vector4_random_predictor_test random_predictor "PASS: randomized image/config dynamic predictor completed"
run_uvm_test vector4_packet_recovery_test packet_recovery "PASS: early/missing TLAST and bad-TKEEP recovery checks completed" "+ALLOW_MALFORMED_INPUT"
run_uvm_test vector4_reset_recovery_test reset_recovery "PASS: reset-during-stalled-output and clean-frame recovery completed"

vcover merge vector_combined.ucdb \
    vector_directed.ucdb \
    vector_backpressure.ucdb \
    vector_busy_write.ucdb \
    vector_saturation.ucdb \
    vector_diagnostics.ucdb \
    vector_wstrb.ucdb \
    vector_axi_protocol.ucdb \
    vector_ral.ucdb \
    vector_random_predictor.ucdb \
    vector_packet_recovery.ucdb \
    vector_reset_recovery.ucdb

vcover report -details vector_combined.ucdb > vector_coverage_report.txt

echo
echo "Vector AXI4-Stream UVM regression passed."
echo "Merged coverage: $ROOT_DIR/vector_combined.ucdb"
echo "Coverage report: $ROOT_DIR/vector_coverage_report.txt"
