#!/usr/bin/env bash
set -euo pipefail
repo_dir=$(cd "$(dirname "$0")/.." && pwd)
ghdl_bin="${GHDL:-ghdl}"
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/gba-cart-vhdl.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
cd "$test_dir"
"$ghdl_bin" -a --std=08 --work=mem "$repo_dir/src/fpga/gba/SyncRamDual.vhd"
"$ghdl_bin" -a --std=08 \
    "$repo_dir/src/fpga/gba/proc_bus_gba.vhd" \
    "$repo_dir/src/fpga/gba/reg_savestates.vhd" \
    "$repo_dir/src/fpga/gba/gba_bios.vhd" \
    "$repo_dir/src/fpga/gba/cache.vhd" \
    "$repo_dir/src/fpga/gba/gba_memorymux.vhd" \
    "$repo_dir/src/fpga/core/cart_save_memorymux_tb.vhd"
"$ghdl_bin" -r --std=08 cart_save_memorymux_tb --assert-level=error --ieee-asserts=disable-at-0
