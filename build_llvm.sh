#!/bin/bash -xe
# SPDX-License-Identifier: Apache-2.0

INSTALLPREFIX="${PWD}/install"
BUILDPREFIX=${PWD}/build
SRCPREFIX=${PWD}

source ./versions.sh
source ./util/util.sh
source ./util/build_runtimes.sh

clone_if_not_exists ${LLVM_BRANCH} https://github.com/axelera-ai/tools.llvm-project.git llvm-project
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

build_compiler_rt ${INSTALLPREFIX} ${BUILDPREFIX} ${INSTALLPREFIX} ${BUILDPREFIX}/llvm/bin/llvm-config ${SRCPREFIX}

if [ "${ENABLE_SPIRV}" = "true" ]; then
    build_spirv ${BUILDPREFIX} ${INSTALLPREFIX} ${BUILDPREFIX}/llvm
else
    echo "[!] Skipping SPIRV tools (ENABLE_SPIRV=${ENABLE_SPIRV})"
fi

# Save variables to a file
echo "[+] Saving variables to toolchain directory"
cp versions.sh ${INSTALLPREFIX}/VERSION-llvm

source util/semver-from-git.sh >> ${INSTALLPREFIX}/VERSION-llvm
