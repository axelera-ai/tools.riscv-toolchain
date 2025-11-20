# Axelera Toolchain Repository [![Release](https://img.shields.io/github/v/release/axelera-ai/tools.riscv-toolchain?sort=semver)](https://github.com/axelera-ai/tools.riscv-toolchain/releases/latest)

This is an internal meta repository for the Axelera RISC-V toolchain(s).

It contains the build script and the build infrastructure to generate an Axelera specific toolchain containing (`clang`, `llvm`, `gcc`, etc.)
We are building two stand-alone toolchains:

- `build_gcc.sh`: Builds a GNU `newlib` toolchain including `libgcc`.
- `build_llvm.sh`: Builds an LLVM-based `newlib` toolchain including `compiler-rt`. Furthemore we build auxiliary tools such as: `SPIRV-Tools` and `SPIRV-LLVM-Translator`.

For both toolchains we build `multilib` versions that are needed within Axelera.

`versions.sh` contains the specific versions used of the upstream projects.
