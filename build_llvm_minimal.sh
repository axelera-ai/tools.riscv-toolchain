#!/bin/bash -xe
# SPDX-License-Identifier: Apache-2.0
# Minimal LLVM toolchain: clang + lld + llvm-ar + compiler-rt only.
# Requires the full toolchain (build_llvm.sh) to be built first for
# compiler-rt cross-compilation.

INSTALLPREFIX="${PWD}/install-llvm-minimal"
BUILDPREFIX=${PWD}/build/llvm-minimal
SRCPREFIX=${PWD}
DEVTOOLCHAIN="${PWD}/install"

source ./versions.sh
source ./util/util.sh
source ./util/build_runtimes.sh

# Verify the full dev toolchain exists
if [ ! -x "${DEVTOOLCHAIN}/bin/clang" ]; then
    echo "Error: Full toolchain not found at ${DEVTOOLCHAIN}. Run build_llvm.sh first."
    exit 1
fi

clone_if_not_exists ${LLVM_BRANCH} https://github.com/axelera-ai/tools.llvm-project.git llvm-project

# ThinLTO only works when building with clang (LLVM_ENABLE_LTO passes clang-style flags)
CMAKE_EXTRA_ARGS=()
if ${CC:-cc} --version 2>&1 | grep -qi clang; then
    CMAKE_EXTRA_ARGS+=(-DLLVM_ENABLE_LTO=Thin)
fi

cmake -S llvm-project/llvm -B ${BUILDPREFIX}/llvm                  \
    -DCMAKE_BUILD_TYPE="MinSizeRel"                                \
    -DCMAKE_INSTALL_PREFIX=${INSTALLPREFIX}                        \
    -DLLVM_TARGETS_TO_BUILD="RISCV"                                \
    -DLLVM_DEFAULT_TARGET_TRIPLE="riscv64-unknown-elf"             \
    -DLLVM_ENABLE_PROJECTS="clang;lld"                             \
    -DCLANG_LINKS_TO_CREATE="riscv64-clang;riscv64-clang++"        \
    -DCLANG_DEFAULT_LINKER=lld                                     \
    -DCLANG_ENABLE_STATIC_ANALYZER=OFF                             \
    -DCLANG_ENABLE_ARCMT=OFF                                       \
    -DCLANG_PLUGIN_SUPPORT=OFF                                     \
    "${CMAKE_EXTRA_ARGS[@]}"                                       \
    -DLLVM_ENABLE_LIBEDIT=OFF                                      \
    -DLLVM_ENABLE_LIBXML2=OFF                                      \
    -DLLVM_ENABLE_ZLIB=OFF                                         \
    -DLLVM_ENABLE_ZSTD=OFF                                         \
    -DLLVM_ENABLE_BINDINGS=OFF                                     \
    -DLLVM_INCLUDE_TESTS=OFF                                       \
    -DLLVM_INCLUDE_EXAMPLES=OFF                                    \
    -DLLVM_INCLUDE_BENCHMARKS=OFF                                  \
    -DLLVM_INCLUDE_DOCS=OFF                                        \
    -DLLVM_BUILD_TESTS=OFF                                         \
    -DLLVM_DISTRIBUTION_COMPONENTS="clang;lld;llvm-ar;clang-resource-headers"

## Build and install (distribution target only installs listed components)
echo "[+] Building and installing minimal LLVM"
cmake --build ${BUILDPREFIX}/llvm -j${NPROC} --target install-distribution

# Strip installed binaries
echo "[+] Stripping binaries"
find ${INSTALLPREFIX}/bin -type f -executable | xargs strip 2>/dev/null || true

build_compiler_rt ${DEVTOOLCHAIN} ${BUILDPREFIX} ${INSTALLPREFIX} ${BUILDPREFIX}/llvm/bin/llvm-config ${SRCPREFIX}

if [ "${ENABLE_SPIRV}" = "true" ]; then
    build_spirv ${BUILDPREFIX} ${INSTALLPREFIX} ${BUILDPREFIX}/llvm
else
    echo "[!] Skipping SPIRV tools (ENABLE_SPIRV=${ENABLE_SPIRV})"
fi

# Save variables to a file
echo "[+] Saving variables to toolchain directory"
cp versions.sh ${INSTALLPREFIX}/VERSION-llvm-minimal
source util/semver-from-git.sh >> ${INSTALLPREFIX}/VERSION-llvm-minimal
