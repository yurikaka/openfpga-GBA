#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Set IVERILOG/VVP to use an unpacked binary distribution.
iverilog_bin="${IVERILOG:-iverilog}"
vvp_bin="${VVP:-vvp}"
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/gba-cart-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT

run_test() {
    local name="$1"
    shift
    "$iverilog_bin" -g2012 -s "$name" -o "$test_dir/$name.vvp" "$@" \
        "src/fpga/core/$name.sv"
    "$vvp_bin" "$test_dir/$name.vvp"
}

run_test save_signature_detector_tb src/fpga/core/save_signature_detector.sv
run_test cart_save_selector_tb src/fpga/core/save_signature_detector.sv \
    src/fpga/core/cart_save_selector.sv
run_test gba_cart_bus_tb src/fpga/core/gba_cart_bus.sv
run_test cart_save_bus_tb src/fpga/core/save_signature_detector.sv \
    src/fpga/core/cart_save_selector.sv src/fpga/core/gba_cart_bus.sv
