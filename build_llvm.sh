#!/bin/bash -xe
# SPDX-License-Identifier: Apache-2.0

INSTALLPREFIX="${PWD}/install"
BUILDPREFIX=${PWD}/build
SRCPREFIX=${PWD}

source ./versions.sh
source ./util/util.sh

clone_if_not_exists ${LLVM_BRANCH} git@github.com:axelera-ai/tools.llvm-project.git llvm-project
cmake -S llvm-project/llvm -B ${BUILDPREFIX}/llvm           \
    -DCMAKE_BUILD_TYPE="Release"                            \
    -DLLVM_USE_SPLIT_DWARF=True                             \
    -DCMAKE_INSTALL_PREFIX=${INSTALLPREFIX}                 \
    -DLLVM_BUILD_TESTS=False                                \
    -DLLVM_DEFAULT_TARGET_TRIPLE="riscv64-unknown-elf"      \
    -DLLVM_TARGETS_TO_BUILD="RISCV"                         \
    -DLLDB_USE_SYSTEM_DEBUGSERVER=ON                        \
    -DLLDB_INCLUDE_TESTS=OFF                                \
    -DCLANG_DEFAULT_LINKER=lld                              \
    -DCLANG_LINKS_TO_CREATE="riscv64-clang;riscv64-clang++" \
    -DLLVM_ENABLE_PROJECTS="clang;lld;lldb;clang-tools-extra"

## Build and install
echo "[+] Building and installing LLVM"
cmake --build ${BUILDPREFIX}/llvm -j${NPROC} --target install

# Copy multilib.yaml to runtime dir
mkdir -p ${INSTALLPREFIX}/lib/clang-runtimes/
cp ${SRCPREFIX}/multilib.yaml ${INSTALLPREFIX}/lib/clang-runtimes/

# Build newlib
clone_if_not_exists ${NEWLIB_BRANCH} https://cygwin.com/git/newlib-cygwin.git newlib

PATH=${INSTALLPREFIX}/bin:${PATH}
mkdir -p ${BUILDPREFIX}/newlib
cd ${BUILDPREFIX}/newlib


CFLAGS_FOR_TARGET="-O2 -mcmodel=medany -Wno-error=implicit-function-declaration" \
CXXFLAGS_FOR_TARGET="-O2 -mcmodel=medany"                                        \
../../newlib/configure                                                           \
    --target=riscv64-unknown-elf                                                 \
    --enable-multilib                                                            \
    --enable-newlib-io-long-double                                               \
    --enable-newlib-io-long-long                                                 \
    --enable-newlib-io-c99-formats                                               \
    --enable-newlib-register-fini                                                \
    --prefix=${BUILDPREFIX}/newlib64                                             \
    AR_FOR_TARGET=${INSTALLPREFIX}/bin/llvm-ar                                   \
    AS_FOR_TARGET=${INSTALLPREFIX}/bin/llvm-as                                   \
    LD_FOR_TARGET=${INSTALLPREFIX}/bin/ld.lld                                    \
    READELF_FOR_TARGET=${INSTALLPREFIX}/bin/llvm-readelf                         \
    RANLIB_FOR_TARGET=${INSTALLPREFIX}/bin/llvm-ranlib                           \
    CC_FOR_TARGET="${INSTALLPREFIX}/bin/clang"                                   \
    ${EXTRA_OPTS}                                                                \
    ${EXTRA_NEWLIB_OPTS}
make -j${NPROC}
make install
cd ../..

for CRT_MULTILIB in $(${INSTALLPREFIX}/bin/clang -target riscv64-unknown-elf -print-multi-lib 2>/dev/null); do
  CRT_MULTILIB_DIR=$(echo ${CRT_MULTILIB} | sed 's/;.*//')
  mkdir -p ${INSTALLPREFIX}/lib/clang-runtimes/${CRT_MULTILIB_DIR}/lib
  cp ${BUILDPREFIX}/newlib64/riscv64-unknown-elf/lib/${CRT_MULTILIB_DIR}/*.a \
      ${INSTALLPREFIX}/lib/clang-runtimes/${CRT_MULTILIB_DIR}/lib
  cp ${BUILDPREFIX}/newlib64/riscv64-unknown-elf/lib/${CRT_MULTILIB_DIR}/*.o \
      ${INSTALLPREFIX}/lib/clang-runtimes/${CRT_MULTILIB_DIR}/lib
  cp ${BUILDPREFIX}/newlib64/riscv64-unknown-elf/lib/${CRT_MULTILIB_DIR}/*.specs \
      ${INSTALLPREFIX}/lib/clang-runtimes/${CRT_MULTILIB_DIR}/lib
  rsync -a ${BUILDPREFIX}/newlib64/riscv64-unknown-elf/include/ \
      ${INSTALLPREFIX}/lib/clang-runtimes/${CRT_MULTILIB_DIR}/include/
done

for CRT_MULTILIB in $(${INSTALLPREFIX}/bin/clang -target riscv64-unknown-elf -print-multi-lib 2>/dev/null); do
    CRT_MULTILIB_DIR=$(echo ${CRT_MULTILIB} | sed 's/;.*//')
    CRT_MULTILIB_OPT=$(echo ${CRT_MULTILIB} | sed 's/.*;//' | sed 's/@/-/' | sed 's/@/ -/g')
    CRT_MULTILIB_BDIR=$(echo ${CRT_MULTILIB} | sed 's/.*;//' | sed 's/@/_/g')
    echo "Multilib: \"${CRT_MULTILIB_DIR}\" -> \"${CRT_MULTILIB_OPT}\""

    cmake -S llvm-project/compiler-rt -B ${BUILDPREFIX}/compiler-rt64${CRT_MULTILIB_BDIR}  \
        -DCMAKE_SYSTEM_NAME=Linux                                                          \
        -DCMAKE_INSTALL_PREFIX=${BUILDPREFIX}/compiler-rt64${CRT_MULTILIB_BDIR}-inst       \
        -DCMAKE_C_COMPILER=${INSTALLPREFIX}/bin/clang${EXE}                                \
        -DCMAKE_CXX_COMPILER=${INSTALLPREFIX}/bin/clang${EXE}                              \
        -DCMAKE_AR=${INSTALLPREFIX}/bin/llvm-ar${EXE}                                      \
        -DCMAKE_NM=${INSTALLPREFIX}/bin/llvm-nm${EXE}                                      \
        -DCMAKE_RANLIB=${INSTALLPREFIX}/bin/llvm-ranlib${EXE}                              \
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
        -DLLVM_CONFIG_PATH=${BUILDPREFIX}/llvm/bin/llvm-config                             \

    echo "[+] Building and installing compiler-rt"
    cmake --build ${BUILDPREFIX}/compiler-rt64${CRT_MULTILIB_BDIR} -j${NPROC} --target install

    cp ${BUILDPREFIX}/compiler-rt64${CRT_MULTILIB_BDIR}-inst/lib/libclang_rt.builtins-riscv64.a \
        ${INSTALLPREFIX}/lib/clang-runtimes/${CRT_MULTILIB_DIR}/lib/libclang_rt.builtins.a
    cp ${BUILDPREFIX}/compiler-rt64${CRT_MULTILIB_BDIR}-inst/lib/clang_rt.crtbegin-riscv64.o \
        ${INSTALLPREFIX}/lib/clang-runtimes/${CRT_MULTILIB_DIR}/lib/clang_rt.crtbegin.o
    cp ${BUILDPREFIX}/compiler-rt64${CRT_MULTILIB_BDIR}-inst/lib/clang_rt.crtend-riscv64.o \
        ${INSTALLPREFIX}/lib/clang-runtimes/${CRT_MULTILIB_DIR}/lib/libclang_rt.crtend.o
done

if [ "${ENABLE_SPIRV}" = "true" ]; then
    # SPIRV-Tools
    clone_if_not_exists ${SPIRV_TOOLS_TAG} https://github.com/KhronosGroup/SPIRV-Tools.git SPIRV-Tools
    cd SPIRV-Tools && python3 utils/git-sync-deps && cd ..

    cmake -S SPIRV-Tools -B ${BUILDPREFIX}/spirv-tools \
        -DCMAKE_BUILD_TYPE="Release"                   \
        -DCMAKE_INSTALL_PREFIX=${INSTALLPREFIX}

    echo "[+] Building and installing SPIRV-Tools"
    cmake --build ${BUILDPREFIX}/spirv-tools -j${NPROC} --target install

    # SPIRV-LLVM-Translator
    clone_if_not_exists ${SPIRV_LLVM_TRANSLATOR_TAG} https://github.com/KhronosGroup/SPIRV-LLVM-Translator.git SPIRV-LLVM-Translator

    cmake -S SPIRV-LLVM-Translator -B ${BUILDPREFIX}/spirv-llvm-translator \
        -DCMAKE_BUILD_TYPE="Release"                                       \
        -DCMAKE_INSTALL_PREFIX=${INSTALLPREFIX}                            \
        -DLLVM_DIR=${BUILDPREFIX}/llvm/lib/cmake/llvm                      \
        -DLLVM_SPIRV_BUILD_EXTERNAL=Yes

    echo "[+] Building and installing SPIRV-LLVM-Translator"
    cmake --build ${BUILDPREFIX}/spirv-llvm-translator -j${NPROC} --target install
else
    echo "[!] Skipping SPIRV tools (ENABLE_SPIRV=${ENABLE_SPIRV})"
fi

# Save variables to a file
echo "[+] Saving variables to toolchain directory"
cp versions.sh ${INSTALLPREFIX}/VERSION-llvm

source util/semver-from-git.sh >> ${INSTALLPREFIX}/VERSION-llvm
