This is an internal meta repository for the Axelera RISC-V toolchain(s).

It references both an internally hosted LLVM repository (with Axelera-specific patches) as well as the upstream RISC-V GNU toolchain meta repository as submodules.
As we reuse parts of the GNU toolchain build (e.g., `libgcc`, `libm`, etc.) also for use with our LLVM toolchain, we must keep both projects in sync.
Hence, each commit in this meta repository is supposed to refer to compatible versions of both toolchains.
