#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

SEED_COUNT="${SEED_COUNT:-100}"

rm -rf work transcript vsim.wlf
rm -f vector_random_seed_*.ucdb vector_random_seed_*.log
rm -f vector_random_multiseed.ucdb vector_random_multiseed_coverage.txt

vlib work
vlog -sv -cover bcesft -f verif/uvm_axis/filelist.f

for seed in $(seq 1 "$SEED_COUNT"); do
    output="vector_random_seed_${seed}"
    echo "Running randomized predictor seed ${seed}/${SEED_COUNT}"
    vsim -c -coverage -assertdebug -onfinish stop \
        -sv_seed "$seed" \
        work.vector_stream_uvm_top \
        +UVM_TESTNAME=vector4_random_predictor_test \
        +UVM_VERBOSITY=UVM_LOW \
        -l "${output}.log" \
        -do "run -all; coverage save ${output}.ucdb; quit -f"

    grep -Eq "UVM_ERROR[[:space:]]*:[[:space:]]*0" "${output}.log"
    grep -Eq "UVM_FATAL[[:space:]]*:[[:space:]]*0" "${output}.log"
    grep -q "PASS: randomized image/config dynamic predictor completed" "${output}.log"
    if grep -Eq "Errors:[[:space:]]*[1-9][0-9]*" "${output}.log"; then
        echo "Simulator error detected in ${output}.log" >&2
        exit 1
    fi
    if grep -Eiq "assertion[^[:space:]]*.*(failed|failure|violation)|\*\* Error:.*assert" \
        "${output}.log"; then
        echo "Assertion failure detected in ${output}.log" >&2
        exit 1
    fi
done

mapfile -t ucdb_files < <(printf '%s\n' vector_random_seed_*.ucdb)
vcover merge vector_random_multiseed.ucdb "${ucdb_files[@]}"
vcover report -details vector_random_multiseed.ucdb > vector_random_multiseed_coverage.txt

echo "Randomized predictor regression passed ${SEED_COUNT}/${SEED_COUNT} seeds."
echo "Merged coverage: $ROOT_DIR/vector_random_multiseed.ucdb"
echo "Coverage report: $ROOT_DIR/vector_random_multiseed_coverage.txt"
