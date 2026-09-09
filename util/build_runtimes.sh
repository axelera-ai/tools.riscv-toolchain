# SPDX-License-Identifier: Apache-2.0
# Shared build functions for compiler-rt and SPIRV tools.

# Build and install compiler-rt builtins for all multilib variants.
#
# Usage: build_compiler_rt <toolchain_prefix> <build_prefix> <install_prefix> <llvm_config_path> <src_prefix>
#   toolchain_prefix: path to the toolchain used for cross-compilation (must have bin/clang, bin/llvm-ar, etc.)
#   build_prefix:     where to place build artifacts
#   install_prefix:   where to install the compiler-rt libraries
#   llvm_config_path: path to llvm-config binary
#   src_prefix:       path to the source tree root (for multilib.yaml)
build_compiler_rt() {
    local TOOLCHAIN=$1
    local BPREFIX=$2
    local IPREFIX=$3
    local LLVM_CONFIG=$4
    local SRC=$5

    mkdir -p ${IPREFIX}/lib/clang-runtimes/
    cp ${SRC}/multilib.yaml ${IPREFIX}/lib/clang-runtimes/

    for CRT_MULTILIB in $(${TOOLCHAIN}/bin/clang -target riscv64-unknown-elf -print-multi-lib 2>/dev/null); do
        CRT_MULTILIB_DIR=$(echo ${CRT_MULTILIB} | sed 's/;.*//')
        CRT_MULTILIB_OPT=$(echo ${CRT_MULTILIB} | sed 's/.*;//' | sed 's/@/-/' | sed 's/@/ -/g')
        CRT_MULTILIB_BDIR=$(echo ${CRT_MULTILIB} | sed 's/.*;//' | sed 's/@/_/g')
        echo "Multilib: \"${CRT_MULTILIB_DIR}\" -> \"${CRT_MULTILIB_OPT}\""

        mkdir -p ${IPREFIX}/lib/clang-runtimes/${CRT_MULTILIB_DIR}/lib

        cmake -S llvm-project/compiler-rt -B ${BPREFIX}/compiler-rt${CRT_MULTILIB_BDIR}       \
            -DCMAKE_SYSTEM_NAME=Linux                                                          \
            -DCMAKE_INSTALL_PREFIX=${BPREFIX}/compiler-rt${CRT_MULTILIB_BDIR}-inst             \
            -DCMAKE_C_COMPILER=${TOOLCHAIN}/bin/clang${EXE}                                    \
            -DCMAKE_CXX_COMPILER=${TOOLCHAIN}/bin/clang${EXE}                                  \
            -DCMAKE_AR=${TOOLCHAIN}/bin/llvm-ar${EXE}                                          \
            -DCMAKE_NM=${TOOLCHAIN}/bin/llvm-nm${EXE}                                          \
            -DCMAKE_RANLIB=${TOOLCHAIN}/bin/llvm-ranlib${EXE}                                  \
            -DCMAKE_C_COMPILER_TARGET="riscv64-unknown-elf"                                    \
            -DCMAKE_CXX_COMPILER_TARGET="riscv64-unknown-elf"                                  \
            -DCMAKE_ASM_COMPILER_TARGET="riscv64-unknown-elf"                                  \
            -DCMAKE_C_FLAGS="${CRT_MULTILIB_OPT} -O2"                                          \
            -DCMAKE_CXX_FLAGS="${CRT_MULTILIB_OPT} -O2"                                        \
            -DCMAKE_ASM_FLAGS="${CRT_MULTILIB_OPT} -O2"                                        \
            -DCMAKE_EXE_LINKER_FLAGS="-nostartfiles -nostdlib"                                 \
            -DCOMPILER_RT_BAREMETAL_BUILD=ON                                                   \
            -DCOMPILER_RT_BUILD_BUILTINS=ON                                                    \
            -DCOMPILER_RT_BUILD_MEMPROF=OFF                                                    \
            -DCOMPILER_RT_BUILD_LIBFUZZER=OFF                                                  \
            -DCOMPILER_RT_BUILD_PROFILE=OFF                                                    \
            -DCOMPILER_RT_BUILD_SANITIZERS=OFF                                                 \
            -DCOMPILER_RT_BUILD_XRAY=OFF                                                       \
            -DCOMPILER_RT_BUILD_CTX_PROFILE=OFF                                                \
            -DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON                                               \
            -DCOMPILER_RT_OS_DIR=""                                                            \
            -DLLVM_CONFIG_PATH=${LLVM_CONFIG}

        echo "[+] Building and installing compiler-rt"
        cmake --build ${BPREFIX}/compiler-rt${CRT_MULTILIB_BDIR} -j${NPROC} --target install

        cp ${BPREFIX}/compiler-rt${CRT_MULTILIB_BDIR}-inst/lib/libclang_rt.builtins-riscv64.a \
            ${IPREFIX}/lib/clang-runtimes/${CRT_MULTILIB_DIR}/lib/libclang_rt.builtins.a
        cp ${BPREFIX}/compiler-rt${CRT_MULTILIB_BDIR}-inst/lib/clang_rt.crtbegin-riscv64.o \
            ${IPREFIX}/lib/clang-runtimes/${CRT_MULTILIB_DIR}/lib/clang_rt.crtbegin.o
        cp ${BPREFIX}/compiler-rt${CRT_MULTILIB_BDIR}-inst/lib/clang_rt.crtend-riscv64.o \
            ${IPREFIX}/lib/clang-runtimes/${CRT_MULTILIB_DIR}/lib/libclang_rt.crtend.o
    done
}

# Build and install SPIRV tools (SPIRV-Tools + SPIRV-LLVM-Translator).
#
# Usage: build_spirv <build_prefix> <install_prefix> <llvm_build_dir>
#   build_prefix:  where to place build artifacts
#   install_prefix: where to install
#   llvm_build_dir: path to the LLVM build directory (containing lib/cmake/llvm)
build_spirv() {
    local BPREFIX=$1
    local IPREFIX=$2
    local LLVM_BUILD=$3

    # SPIRV-Tools
    clone_if_not_exists ${SPIRV_TOOLS_TAG} https://github.com/KhronosGroup/SPIRV-Tools.git SPIRV-Tools
    cd SPIRV-Tools && python3 utils/git-sync-deps && cd ..

    cmake -S SPIRV-Tools -B ${BPREFIX}/spirv-tools \
        -DCMAKE_BUILD_TYPE="Release"               \
        -DCMAKE_INSTALL_PREFIX=${IPREFIX}

    echo "[+] Building and installing SPIRV-Tools"
    cmake --build ${BPREFIX}/spirv-tools -j${NPROC} --target install

    # SPIRV-LLVM-Translator
    clone_if_not_exists ${SPIRV_LLVM_TRANSLATOR_TAG} https://github.com/KhronosGroup/SPIRV-LLVM-Translator.git SPIRV-LLVM-Translator

    cmake -S SPIRV-LLVM-Translator -B ${BPREFIX}/spirv-llvm-translator \
        -DCMAKE_BUILD_TYPE="Release"                                   \
        -DCMAKE_INSTALL_PREFIX=${IPREFIX}                              \
        -DLLVM_DIR=${LLVM_BUILD}/lib/cmake/llvm                        \
        -DLLVM_SPIRV_BUILD_EXTERNAL=Yes

    echo "[+] Building and installing SPIRV-LLVM-Translator"
    cmake --build ${BPREFIX}/spirv-llvm-translator -j${NPROC} --target install
}
