#!/bin/bash -xe
# SPDX-License-Identifier: Apache-2.0
#
# Cross-compile the RISC-V LLVM toolchain for Android (aarch64-linux-android)
# using Android NDK r23c already installed on this machine.
#
# What this produces:
#   install-android/bin/clang, llvm-ar, ld.lld, ...  — run on Android arm64-v8a (API 28+)
#   install-android/lib/clang-runtimes/*/lib/*.a       — RISC-V bare-metal libs (host-agnostic)
#
# Two-stage build:
#   Stage 1  (native x86_64): build llvm-tblgen, clang-tblgen, and a native riscv64 clang
#            These tools must run on the build machine and cannot be skipped.
#   Stage 2  (Android aarch64): cross-compile LLVM using NDK r23c as the host compiler,
#            pointing tblgen at the Stage 1 binaries.
#   newlib / compiler-rt are compiled with the Stage 1 native clang (they target RISC-V,
#            so the host arch of the compiler does not matter for the output .a files).

INSTALLPREFIX="${PWD}/install-android"
BUILDPREFIX="${PWD}/build"
SRCPREFIX="${PWD}"

source ./versions.sh
source ./util/util.sh

# ---- Android NDK configuration ----
NDK_ROOT="${ANDROID_NDK_HOME:-/home/ubuntu/android-ndk-r23c}"
ANDROID_API=28
ANDROID_TRIPLE="aarch64-linux-android${ANDROID_API}"
TOOLCHAIN="${NDK_ROOT}/toolchains/llvm/prebuilt/linux-x86_64"
NDK_CLANG="${TOOLCHAIN}/bin/clang"
NDK_CLANGXX="${TOOLCHAIN}/bin/clang++"
NDK_SYSROOT="${TOOLCHAIN}/sysroot"

if [ ! -x "${NDK_CLANG}" ]; then
    echo "[!] NDK clang not found at ${NDK_CLANG}"
    echo "[!] Set ANDROID_NDK_HOME or install NDK r23c at /home/ubuntu/android-ndk-r23c"
    exit 1
fi

echo "[+] NDK root: ${NDK_ROOT}"
echo "[+] Build target: ${ANDROID_TRIPLE}"
echo "[+] RISC-V target: riscv64-unknown-elf"

clone_if_not_exists ${LLVM_BRANCH} git@github.com:axelera-ai/tools.llvm-project.git llvm-project

# ============================================================
# Stage 1: Native x86_64 build
# Produces: llvm-tblgen, clang-tblgen, and a native clang that
# can cross-compile newlib/compiler-rt to riscv64-unknown-elf.
# ============================================================
echo "[+] Stage 1: Building native LLVM (x86_64 host tools + riscv64 cross-compiler)"
cmake -S llvm-project/llvm -B ${BUILDPREFIX}/llvm-native  \
    -DCMAKE_BUILD_TYPE="Release"                           \
    -DLLVM_BUILD_TESTS=False                               \
    -DLLVM_TARGETS_TO_BUILD="RISCV;X86"                    \
    -DLLVM_DEFAULT_TARGET_TRIPLE="riscv64-unknown-elf"     \
    -DLLVM_ENABLE_PROJECTS="clang;lld"                     \
    -DCLANG_DEFAULT_LINKER=lld                             \
    -DCLANG_LINKS_TO_CREATE="riscv64-clang;riscv64-clang++" \
    -DLLDB_INCLUDE_TESTS=OFF

# Build only what we need from Stage 1 (tblgen + clang + lld tools)
cmake --build ${BUILDPREFIX}/llvm-native -j${NPROC} \
    --target llvm-tblgen clang-tblgen llvm-ar llvm-nm llvm-ranlib llvm-as \
            llvm-readelf ld.lld clang llvm-config

NATIVE_TBLGEN="${BUILDPREFIX}/llvm-native/bin/llvm-tblgen"
NATIVE_CLANG_TBLGEN="${BUILDPREFIX}/llvm-native/bin/clang-tblgen"
NATIVE_CLANG="${BUILDPREFIX}/llvm-native/bin/clang"
NATIVE_AR="${BUILDPREFIX}/llvm-native/bin/llvm-ar"
NATIVE_AS="${BUILDPREFIX}/llvm-native/bin/llvm-as"
NATIVE_LLD="${BUILDPREFIX}/llvm-native/bin/ld.lld"
NATIVE_NM="${BUILDPREFIX}/llvm-native/bin/llvm-nm"
NATIVE_RANLIB="${BUILDPREFIX}/llvm-native/bin/llvm-ranlib"
NATIVE_READELF="${BUILDPREFIX}/llvm-native/bin/llvm-readelf"
NATIVE_LLVM_CONFIG="${BUILDPREFIX}/llvm-native/bin/llvm-config"

# ============================================================
# Stage 2: Cross-compile LLVM for Android aarch64
# The resulting binaries will run on Android arm64-v8a API 28+.
# ============================================================
echo "[+] Stage 2: Cross-compiling LLVM for Android (${ANDROID_TRIPLE})"

cmake -S llvm-project/llvm -B ${BUILDPREFIX}/llvm-android   \
    -DCMAKE_BUILD_TYPE="Release"                             \
    -DCMAKE_INSTALL_PREFIX=${INSTALLPREFIX}                  \
    -DCMAKE_C_COMPILER="${NDK_CLANG}"                        \
    -DCMAKE_CXX_COMPILER="${NDK_CLANGXX}"                    \
    -DCMAKE_C_COMPILER_TARGET="${ANDROID_TRIPLE}"            \
    -DCMAKE_CXX_COMPILER_TARGET="${ANDROID_TRIPLE}"          \
    -DCMAKE_ASM_COMPILER_TARGET="${ANDROID_TRIPLE}"          \
    -DCMAKE_SYSROOT="${NDK_SYSROOT}"                         \
    -DLLVM_HOST_TRIPLE="aarch64-linux-android"               \
    -DLLVM_TABLEGEN="${NATIVE_TBLGEN}"                       \
    -DCLANG_TABLEGEN="${NATIVE_CLANG_TBLGEN}"                \
    -DLLVM_USE_SPLIT_DWARF=True                              \
    -DLLVM_BUILD_TESTS=False                                 \
    -DLLVM_DEFAULT_TARGET_TRIPLE="riscv64-unknown-elf"       \
    -DLLVM_TARGETS_TO_BUILD="RISCV"                          \
    -DLLVM_ENABLE_PROJECTS="clang;lld;clang-tools-extra"     \
    -DCLANG_DEFAULT_LINKER=lld                               \
    -DCLANG_LINKS_TO_CREATE="riscv64-clang;riscv64-clang++"  \
    -DLLDB_INCLUDE_TESTS=OFF                                 \
    -DLLVM_ENABLE_TERMINFO=OFF                               \
    -DLLVM_ENABLE_LIBEDIT=OFF                                \
    -DLLVM_ENABLE_LIBXML2=OFF                                \
    -DLLVM_BUILD_STATIC=OFF

echo "[+] Building and installing Android LLVM"
cmake --build ${BUILDPREFIX}/llvm-android -j${NPROC} --target install

# Copy multilib.yaml to runtime dir
mkdir -p ${INSTALLPREFIX}/lib/clang-runtimes/
cp ${SRCPREFIX}/multilib.yaml ${INSTALLPREFIX}/lib/clang-runtimes/

# ============================================================
# Build newlib using Stage 1 native clang (targeting riscv64-unknown-elf)
# The output .a files are RISC-V arch and are host-agnostic.
# ============================================================
echo "[+] Building newlib (native clang cross-compiling to riscv64-unknown-elf)"
clone_if_not_exists ${NEWLIB_BRANCH} https://cygwin.com/git/newlib-cygwin.git newlib

mkdir -p ${BUILDPREFIX}/newlib
cd ${BUILDPREFIX}/newlib

CFLAGS_FOR_TARGET="-O2 -mcmodel=medany -Wno-error=implicit-function-declaration" \
CXXFLAGS_FOR_TARGET="-O2 -mcmodel=medany"                                        \
../../newlib/configure                                                            \
    --target=riscv64-unknown-elf                                                  \
    --enable-multilib                                                             \
    --enable-newlib-io-long-double                                                \
    --enable-newlib-io-long-long                                                  \
    --enable-newlib-io-c99-formats                                                \
    --enable-newlib-register-fini                                                 \
    --prefix=${BUILDPREFIX}/newlib64                                              \
    AR_FOR_TARGET=${NATIVE_AR}                                                    \
    AS_FOR_TARGET=${NATIVE_AS}                                                    \
    LD_FOR_TARGET=${NATIVE_LLD}                                                   \
    READELF_FOR_TARGET=${NATIVE_READELF}                                          \
    RANLIB_FOR_TARGET=${NATIVE_RANLIB}                                            \
    CC_FOR_TARGET="${NATIVE_CLANG}"                                               \
    ${EXTRA_OPTS}                                                                 \
    ${EXTRA_NEWLIB_OPTS}
make -j${NPROC}
make install
cd ${SRCPREFIX}

# Copy newlib libraries into the Android install dir
for CRT_MULTILIB in $(${NATIVE_CLANG} -target riscv64-unknown-elf -print-multi-lib 2>/dev/null); do
  CRT_MULTILIB_DIR=$(echo ${CRT_MULTILIB} | sed 's/;.*//')
  mkdir -p ${INSTALLPREFIX}/lib/clang-runtimes/${CRT_MULTILIB_DIR}/lib
  cp ${BUILDPREFIX}/newlib64/riscv64-unknown-elf/lib/${CRT_MULTILIB_DIR}/*.a \
      ${INSTALLPREFIX}/lib/clang-runtimes/${CRT_MULTILIB_DIR}/lib
  cp ${BUILDPREFIX}/newlib64/riscv64-unknown-elf/lib/${CRT_MULTILIB_DIR}/*.o \
      ${INSTALLPREFIX}/lib/clang-runtimes/${CRT_MULTILIB_DIR}/lib
  cp ${BUILDPREFIX}/newlib64/riscv64-unknown-elf/lib/${CRT_MULTILIB_DIR}/*.specs \
      ${INSTALLPREFIX}/lib/clang-runtimes/${CRT_MULTILIB_DIR}/lib 2>/dev/null || true
  rsync -a ${BUILDPREFIX}/newlib64/riscv64-unknown-elf/include/ \
      ${INSTALLPREFIX}/lib/clang-runtimes/${CRT_MULTILIB_DIR}/include/
done

# ============================================================
# Build compiler-rt using Stage 1 native clang (targeting riscv64-unknown-elf)
# ============================================================
for CRT_MULTILIB in $(${NATIVE_CLANG} -target riscv64-unknown-elf -print-multi-lib 2>/dev/null); do
    CRT_MULTILIB_DIR=$(echo ${CRT_MULTILIB} | sed 's/;.*//')
    CRT_MULTILIB_OPT=$(echo ${CRT_MULTILIB} | sed 's/.*;//' | sed 's/@/-/' | sed 's/@/ -/g')
    CRT_MULTILIB_BDIR=$(echo ${CRT_MULTILIB} | sed 's/.*;//' | sed 's/@/_/g')
    echo "Multilib: \"${CRT_MULTILIB_DIR}\" -> \"${CRT_MULTILIB_OPT}\""

    cmake -S llvm-project/compiler-rt -B ${BUILDPREFIX}/compiler-rt64${CRT_MULTILIB_BDIR}   \
        -DCMAKE_SYSTEM_NAME=Linux                                                            \
        -DCMAKE_INSTALL_PREFIX=${BUILDPREFIX}/compiler-rt64${CRT_MULTILIB_BDIR}-inst         \
        -DCMAKE_C_COMPILER=${NATIVE_CLANG}                                                   \
        -DCMAKE_CXX_COMPILER=${NATIVE_CLANG}                                                 \
        -DCMAKE_AR=${NATIVE_AR}                                                              \
        -DCMAKE_NM=${NATIVE_NM}                                                              \
        -DCMAKE_RANLIB=${NATIVE_RANLIB}                                                      \
        -DCMAKE_C_COMPILER_TARGET="riscv64-unknown-elf"                                      \
        -DCMAKE_CXX_COMPILER_TARGET="riscv64-unknown-elf"                                    \
        -DCMAKE_ASM_COMPILER_TARGET="riscv64-unknown-elf"                                    \
        -DCMAKE_C_FLAGS="${CRT_MULTILIB_OPT} -O2"                                            \
        -DCMAKE_CXX_FLAGS="${CRT_MULTILIB_OPT} -O2"                                          \
        -DCMAKE_ASM_FLAGS="${CRT_MULTILIB_OPT} -O2"                                          \
        -DCMAKE_EXE_LINKER_FLAGS="-nostartfiles -nostdlib"                                   \
        -DCOMPILER_RT_BAREMETAL_BUILD=ON                                                     \
        -DCOMPILER_RT_BUILD_BUILTINS=ON                                                      \
        -DCOMPILER_RT_BUILD_MEMPROF=OFF                                                      \
        -DCOMPILER_RT_BUILD_LIBFUZZER=OFF                                                    \
        -DCOMPILER_RT_BUILD_PROFILE=OFF                                                      \
        -DCOMPILER_RT_BUILD_SANITIZERS=OFF                                                   \
        -DCOMPILER_RT_BUILD_XRAY=OFF                                                         \
        -DCOMPILER_RT_BUILD_CTX_PROFILE=OFF                                                  \
        -DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON                                                 \
        -DCOMPILER_RT_OS_DIR=""                                                              \
        -DLLVM_CONFIG_PATH=${NATIVE_LLVM_CONFIG}

    echo "[+] Building and installing compiler-rt (${CRT_MULTILIB_DIR})"
    cmake --build ${BUILDPREFIX}/compiler-rt64${CRT_MULTILIB_BDIR} -j${NPROC} --target install

    cp ${BUILDPREFIX}/compiler-rt64${CRT_MULTILIB_BDIR}-inst/lib/libclang_rt.builtins-riscv64.a \
        ${INSTALLPREFIX}/lib/clang-runtimes/${CRT_MULTILIB_DIR}/lib/libclang_rt.builtins.a
    cp ${BUILDPREFIX}/compiler-rt64${CRT_MULTILIB_BDIR}-inst/lib/clang_rt.crtbegin-riscv64.o \
        ${INSTALLPREFIX}/lib/clang-runtimes/${CRT_MULTILIB_DIR}/lib/clang_rt.crtbegin.o
    cp ${BUILDPREFIX}/compiler-rt64${CRT_MULTILIB_BDIR}-inst/lib/clang_rt.crtend-riscv64.o \
        ${INSTALLPREFIX}/lib/clang-runtimes/${CRT_MULTILIB_DIR}/lib/libclang_rt.crtend.o
done

# SPIRV: cross-compilation for Android not yet adapted
if [ "${ENABLE_SPIRV}" = "true" ]; then
    echo "[!] SPIRV cross-compilation for Android is not yet supported in this script"
else
    echo "[!] Skipping SPIRV tools (ENABLE_SPIRV=${ENABLE_SPIRV})"
fi

# Save version info
echo "[+] Saving variables to toolchain directory"
cp versions.sh ${INSTALLPREFIX}/VERSION-llvm
source util/semver-from-git.sh >> ${INSTALLPREFIX}/VERSION-llvm

echo ""
echo "[+] Done!"
echo "[+] Android toolchain installed to: ${INSTALLPREFIX}"
echo "[+] Binaries run on:  aarch64-linux-android${ANDROID_API} (arm64-v8a)"
echo "[+] Toolchain target: riscv64-unknown-elf"
echo ""
echo "[+] To use on device, push ${INSTALLPREFIX} to Android and invoke:"
echo "    ./clang --target=riscv64-unknown-elf <sources>"
