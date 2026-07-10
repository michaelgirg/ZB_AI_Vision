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

    vsim -c -coverage -assertdebug -onfinish stop \
        -sv_seed 24601 \
        work.vector_stream_uvm_top \
        "+UVM_TESTNAME=${test_name}" \
        +UVM_VERBOSITY=UVM_MEDIUM \
        +INPUT_MEM=generated/test_vectors/sample_000_input.mem \
        +EXPECTED_MEM=generated/test_vectors/sample_000_conv4.mem \
        -l "vector_${output_name}.log" \
        -do "run -all; coverage save vector_${output_name}.ucdb; quit -f"

    grep -Eq "UVM_ERROR[[:space:]]*:[[:space:]]*0" "vector_${output_name}.log"
    grep -Eq "UVM_FATAL[[:space:]]*:[[:space:]]*0" "vector_${output_name}.log"
    grep -q "PASS: matched 784 packed vector outputs" "vector_${output_name}.log"
}

run_uvm_test vector4_stream_test directed
run_uvm_test vector4_backpressure_test backpressure
run_uvm_test vector4_busy_write_test busy_write
run_uvm_test vector4_saturation_test saturation

vcover merge vector_combined.ucdb \
    vector_directed.ucdb \
    vector_backpressure.ucdb \
    vector_busy_write.ucdb \
    vector_saturation.ucdb

vcover report -details vector_combined.ucdb > vector_coverage_report.txt

echo
echo "Vector AXI4-Stream UVM regression passed."
echo "Merged coverage: $ROOT_DIR/vector_combined.ucdb"
echo "Coverage report: $ROOT_DIR/vector_coverage_report.txt"
