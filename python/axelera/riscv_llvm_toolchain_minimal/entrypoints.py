#!/usr/bin/env python3
"""Entrypoint wrappers for RISC-V LLVM minimal toolchain binaries."""

import os
import sys
from pathlib import Path
from typing import NoReturn


def _get_bin_dir() -> Path:
    module_dir = Path(__file__).parent
    return module_dir / "bin"


def _exec_binary(binary_name: str) -> NoReturn:
    bin_dir = _get_bin_dir()
    binary_path = bin_dir / binary_name

    if not binary_path.exists():
        print(f"Error: Binary not found: {binary_path}", file=sys.stderr)
        sys.exit(1)

    os.execv(str(binary_path), [str(binary_path)] + sys.argv[1:])


def clang() -> NoReturn:
    _exec_binary("clang")


def clangxx() -> NoReturn:
    _exec_binary("clang++")


def clang_cpp() -> NoReturn:
    _exec_binary("clang-cpp")


def riscv64_clang() -> NoReturn:
    _exec_binary("riscv64-clang")


def riscv64_clangxx() -> NoReturn:
    _exec_binary("riscv64-clang++")


def lld() -> NoReturn:
    _exec_binary("lld")


def ld_lld() -> NoReturn:
    _exec_binary("ld.lld")


def ld64_lld() -> NoReturn:
    _exec_binary("ld64.lld")


def wasm_ld() -> NoReturn:
    _exec_binary("wasm-ld")


def lld_link() -> NoReturn:
    _exec_binary("lld-link")


def llvm_ar() -> NoReturn:
    _exec_binary("llvm-ar")
