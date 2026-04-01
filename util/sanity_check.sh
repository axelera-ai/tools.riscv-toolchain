#!/bin/bash -e
# SPDX-License-Identifier: Apache-2.0
# Sanity check a built toolchain for completeness.
#
# Usage: util/sanity_check.sh <toolchain> [install_prefix]
#   toolchain:      "llvm" or "gcc"
#   install_prefix: path to the install directory (default: ./install)

TOOLCHAIN="${1:?Usage: $0 <llvm|gcc> [install_prefix]}"
PREFIX="${2:-install}"

FAIL=0

check() {
    if [ ! -e "$1" ]; then
        echo "FAIL: missing $1"
        FAIL=1
    fi
}

if [ "$TOOLCHAIN" = "llvm" ]; then
    # Verify clang can compile a minimal program
    echo 'int main() { return 0; }' | \
        ${PREFIX}/bin/clang --target=riscv64-unknown-elf -x c -c - -o /dev/null \
        || { echo "FAIL: clang cannot compile"; FAIL=1; }

    # Verify all expected multilib variants have newlib headers and compiler-rt
    for dir in \
        riscv64-unknown-elf/rv64ima/lp64 \
        riscv64-unknown-elf/rv64imac/lp64 \
        riscv64-unknown-elf/rv64imafdc/lp64f \
        riscv64-unknown-elf/rv64imafdc/lp64d; do
        check "${PREFIX}/lib/clang-runtimes/${dir}/include/assert.h"
        check "${PREFIX}/lib/clang-runtimes/${dir}/lib/libclang_rt.builtins.a"
    done

    check "${PREFIX}/lib/clang-runtimes/multilib.yaml"

elif [ "$TOOLCHAIN" = "gcc" ]; then
    # Verify key binaries exist
    for bin in gcc g++ gdb ld as objdump; do
        check "${PREFIX}/bin/riscv64-unknown-elf-${bin}"
    done

    # Verify multilib support (should have multiple lib dirs)
    MULTILIB_COUNT=$(find "${PREFIX}/lib/gcc/riscv64-unknown-elf" -name "libgcc.a" | wc -l)
    if [ "$MULTILIB_COUNT" -lt 2 ]; then
        echo "FAIL: expected multiple multilib variants, found ${MULTILIB_COUNT}"
        FAIL=1
    fi
else
    echo "Unknown toolchain: ${TOOLCHAIN}"
    exit 1
fi

if [ "$FAIL" -ne 0 ]; then
    echo "Sanity check FAILED"
    exit 1
fi
echo "All sanity checks passed"
