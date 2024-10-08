This is an internal meta repository for the Axelera RISC-V toolchain(s).

It contains the build script and the build infrastructure to generate an Axelera specific toolchain containing (`clang`, `llvm`, `gcc`, etc.)
As we reuse parts of the GNU toolchain build (e.g., `libgcc`, `libm`, etc.) also for use with our LLVM toolchain, we must keep both projects in sync.

`versions.sh` contains the specific versions used of the upstream projects.
