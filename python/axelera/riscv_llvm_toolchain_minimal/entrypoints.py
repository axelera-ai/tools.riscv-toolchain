#!/usr/bin/env python3
"""Entrypoint wrappers for RISC-V LLVM minimal toolchain binaries.

The wheel ships only the canonical multicall binaries (clang, ld.lld, llvm-ar).
Each entrypoint execs one of these with the desired argv[0] so the binary picks
the right driver mode / target / linker flavour. This avoids shipping multiple
copies of the same binary inside the wheel, since the wheel (zip) format has
no portable symlink encoding.

ld.lld is the canonical lld multicall binary (bit-identical to upstream lld);
the bare 'lld' name is kept as an entrypoint for completeness but execs ld.lld
with argv[0]='lld', which prints lld's usage message — same as upstream.
"""

import os
import sys
from pathlib import Path
from typing import NoReturn


def _get_bin_dir() -> Path:
    return Path(__file__).parent / "bin"


def _exec_as(canonical_binary: str, argv0_name: str) -> NoReturn:
    binary_path = _get_bin_dir() / canonical_binary

    if not binary_path.exists():
        print(f"Error: Binary not found: {binary_path}", file=sys.stderr)
        sys.exit(1)

    os.execv(str(binary_path), [argv0_name] + sys.argv[1:])


def clang() -> NoReturn:
    _exec_as("clang", "clang")


def clangxx() -> NoReturn:
    _exec_as("clang", "clang++")


def riscv64_clang() -> NoReturn:
    _exec_as("clang", "riscv64-clang")


def riscv64_clangxx() -> NoReturn:
    _exec_as("clang", "riscv64-clang++")


def lld() -> NoReturn:
    _exec_as("ld.lld", "lld")


def ld_lld() -> NoReturn:
    # ld.lld is the only lld-family binary physically present in the wheel,
    # because the bundled clang's auto-detect (dirname(clang)/ld.lld) needs
    # to find it without falling back to $PATH.
    _exec_as("ld.lld", "ld.lld")


def ld64_lld() -> NoReturn:
    _exec_as("ld.lld", "ld64.lld")


def wasm_ld() -> NoReturn:
    _exec_as("ld.lld", "wasm-ld")


def lld_link() -> NoReturn:
    _exec_as("ld.lld", "lld-link")


def llvm_ar() -> NoReturn:
    _exec_as("llvm-ar", "llvm-ar")
