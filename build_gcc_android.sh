#!/bin/bash -xe
# SPDX-License-Identifier: Apache-2.0
#
# Canadian-cross build of the RISC-V GCC toolchain for Android (aarch64-linux-android).
# Uses Android NDK r23c already installed on this machine.
#
# What this produces:
#   install-android-gcc/bin/riscv64-unknown-elf-gcc, g++, ld, ...  — run on Android arm64-v8a
#   install-android-gcc/riscv64-unknown-elf/lib/*.a                 — RISC-V bare-metal libs
#
# Build triple:
#   --build  = x86_64-linux-gnu         (this machine, runs configure/make)
#   --host   = aarch64-linux-android    (Android device, runs the produced toolchain)
#   --target = riscv64-unknown-elf      (what the toolchain compiles for)
#
# Phases:
#   Phase 1  Native x86_64 binutils + GCC stage1 + newlib + GCC stage2
#            Needed to produce newlib for the Android GCC sysroot, and to
#            provide CC_FOR_BUILD for internal GCC generators.
#   Phase 2  Cross-compile GMP, MPFR, MPC for Android host (statically linked into GCC).
#   Phase 3  Android binutils  (Canadian cross, --build/--host/--target as above).
#   Phase 4  Android GCC       (Canadian cross, uses newlib from Phase 1 as sysroot).
#
# GDB is skipped: it requires Python, readline, and ncurses compiled for Android,
# which is out of scope. Use the LLVM toolchain's lldb if on-device debugging is needed.

INSTALLPREFIX="${PWD}/install-android-gcc"
BUILDPREFIX="${PWD}/build"
SRCPREFIX="${PWD}"
MULTILIB_GENERATOR="rv64i-lp64--c rv64ia-lp64--m rv64im-lp64--c rv64if-lp64f-rv64ifd-c rv64iaf-lp64f-rv64imaf,rv64iafc-d rv64imf-lp64f-rv64imfd-c rv64iac-lp64-- rv64imac-lp64-- rv64imafc-lp64f-rv64imafdc- rv64ifd-lp64d--m,c rv64iafd-lp64d-rv64imafd,rv64iafdc- rv64imafdc-lp64d--"

source ./versions.sh
source ./util/util.sh

# ---- Android NDK configuration ----
NDK_ROOT="${ANDROID_NDK_HOME:-/home/ubuntu/android-ndk-r23c}"
ANDROID_API=28
TOOLCHAIN="${NDK_ROOT}/toolchains/llvm/prebuilt/linux-x86_64"

# Versioned wrapper scripts set --target and --sysroot automatically.
NDK_CC="${TOOLCHAIN}/bin/aarch64-linux-android${ANDROID_API}-clang"
NDK_CXX="${TOOLCHAIN}/bin/aarch64-linux-android${ANDROID_API}-clang++"
NDK_AR="${TOOLCHAIN}/bin/llvm-ar"
NDK_RANLIB="${TOOLCHAIN}/bin/llvm-ranlib"
NDK_NM="${TOOLCHAIN}/bin/llvm-nm"
NDK_STRIP="${TOOLCHAIN}/bin/llvm-strip"

if [ ! -x "${NDK_CC}" ]; then
    echo "[!] NDK clang not found at ${NDK_CC}"
    echo "[!] Set ANDROID_NDK_HOME or install NDK r23c at /home/ubuntu/android-ndk-r23c"
    exit 1
fi

echo "[+] NDK root:   ${NDK_ROOT}"
echo "[+] Host target: aarch64-linux-android${ANDROID_API}"
echo "[+] RISC-V target: riscv64-unknown-elf"

# Prefix for Phase 1 native tools (temporary, used only for bootstrap)
NATIVE_INSTALL="${BUILDPREFIX}/native-install"
# Prefix for Android-compiled GMP/MPFR/MPC (linked into the Android GCC binary)
ANDROID_PREREQS="${BUILDPREFIX}/android-prereqs"

# ============================================================
# Phase 1: Native x86_64 tools (bootstrap)
# Builds: binutils, GCC stage1, newlib, GCC stage2 — all native (x86_64 host,
# riscv64-unknown-elf target). The newlib install becomes the sysroot for the
# Android GCC. The native GCC provides CC_FOR_BUILD for GCC's own generators.
# ============================================================

# --- Binutils (native) ---
echo "[+] Phase 1a: Native binutils (riscv64-unknown-elf)"
clone_if_not_exists ${BINUTILS_BRANCH} https://gnu.googlesource.com/binutils-gdb

mkdir -p ${BUILDPREFIX}/binutils-native
cd ${BUILDPREFIX}/binutils-native

CFLAGS="-O2 -Wno-error=implicit-function-declaration"   \
CXXFLAGS="-O2 -Wno-error=implicit-function-declaration" \
../../binutils-gdb/configure                            \
    --target=riscv64-unknown-elf                        \
    --prefix=${NATIVE_INSTALL}                          \
    --disable-werror                                    \
    --disable-gdb                                       \
    --disable-sim                                       \
    --disable-libdecnumber                              \
    --disable-readline                                  \
    ${EXTRA_OPTS}                                       \
    ${EXTRA_BINUTILS_OPTS}
make -j${NPROC}
make install
cd ${SRCPREFIX}

# --- GCC sources + prerequisites ---
echo "[+] Phase 1b: GCC sources and prerequisites"
clone_if_not_exists ${GCC_BRANCH} https://gnu.googlesource.com/gcc
cd gcc
./contrib/download_prerequisites   # downloads GMP, MPFR, MPC, isl in-tree
cd ${SRCPREFIX}

# --- GCC Stage 1 (native, C only — needed to compile newlib) ---
echo "[+] Phase 1c: Native GCC Stage 1 (C only, riscv64-unknown-elf)"
mkdir -p ${BUILDPREFIX}/gcc-native-stage1
cd ${BUILDPREFIX}/gcc-native-stage1

../../gcc/configure                                         \
    --target=riscv64-unknown-elf                            \
    --prefix=${NATIVE_INSTALL}                              \
    --with-sysroot=${NATIVE_INSTALL}/riscv64-unknown-elf    \
    --with-newlib                                           \
    --without-headers                                       \
    --disable-shared                                        \
    --enable-languages=c                                    \
    --disable-werror                                        \
    --disable-libatomic                                     \
    --disable-libmudflap                                    \
    --disable-libssp                                        \
    --disable-quadmath                                      \
    --disable-libgomp                                       \
    --disable-nls                                           \
    --disable-bootstrap                                     \
    --enable-multilib                                       \
    --with-multilib-generator="${MULTILIB_GENERATOR}"       \
    --with-arch=${DEFAULTARCH}                              \
    --with-abi=${DEFAULTABI}                                \
    CFLAGS_FOR_TARGET="-O2 -mcmodel=medany"                 \
    CXXFLAGS_FOR_TARGET="-O2 -mcmodel=medany"               \
    ${EXTRA_OPTS}                                           \
    ${EXTRA_GCC_OPTS}
make -j${NPROC}
make install
cd ${SRCPREFIX}

# --- Newlib (using native Stage 1 GCC) ---
echo "[+] Phase 1d: Newlib (native GCC, targeting riscv64-unknown-elf)"
clone_if_not_exists ${NEWLIB_BRANCH} https://cygwin.com/git/newlib-cygwin.git newlib

PATH=${NATIVE_INSTALL}/bin:${PATH}
mkdir -p ${BUILDPREFIX}/newlib-native
cd ${BUILDPREFIX}/newlib-native

CFLAGS_FOR_TARGET="-O2 -mcmodel=medany -Wno-error=implicit-function-declaration" \
CXXFLAGS_FOR_TARGET="-O2 -mcmodel=medany"                                        \
../../newlib/configure                                                            \
    --target=riscv64-unknown-elf                                                  \
    --prefix=${NATIVE_INSTALL}                                                    \
    --with-arch=${DEFAULTARCH}                                                    \
    --with-abi=${DEFAULTABI}                                                      \
    --enable-multilib                                                             \
    --enable-newlib-io-long-double                                                \
    --enable-newlib-io-long-long                                                  \
    --enable-newlib-io-c99-formats                                                \
    --enable-newlib-register-fini                                                 \
    ${EXTRA_OPTS}                                                                 \
    ${EXTRA_NEWLIB_OPTS}
make -j${NPROC}
make install
cd ${SRCPREFIX}

# --- GCC Stage 2 (native, C + C++ — provides the full sysroot for Android GCC) ---
echo "[+] Phase 1e: Native GCC Stage 2 (C + C++, riscv64-unknown-elf)"
mkdir -p ${BUILDPREFIX}/gcc-native-stage2
cd ${BUILDPREFIX}/gcc-native-stage2

../../gcc/configure                                         \
    --target=riscv64-unknown-elf                            \
    --prefix=${NATIVE_INSTALL}                              \
    --with-sysroot=${NATIVE_INSTALL}/riscv64-unknown-elf    \
    --with-native-system-header-dir=/include                \
    --with-newlib                                           \
    --enable-languages=c,c++                                \
    --enable-tls                                            \
    --disable-werror                                        \
    --disable-libmudflap                                    \
    --disable-libssp                                        \
    --disable-quadmath                                      \
    --disable-libgomp                                       \
    --disable-nls                                           \
    --enable-multilib                                       \
    --with-multilib-generator="${MULTILIB_GENERATOR}"       \
    --with-arch=${DEFAULTARCH}                              \
    --with-abi=${DEFAULTABI}                                \
    CFLAGS_FOR_TARGET="-O2 -mcmodel=medany"                 \
    CXXFLAGS_FOR_TARGET="-O2 -mcmodel=medany"               \
    ${EXTRA_OPTS}                                           \
    ${EXTRA_GCC_OPTS}
make -j${NPROC}
make install
cd ${SRCPREFIX}

# ============================================================
# Phase 2: Cross-compile GMP, MPFR, MPC for Android host
# These are linked statically into the Android GCC binary.
# We use the same sources already downloaded by download_prerequisites.
# ============================================================
echo "[+] Phase 2: Building GMP, MPFR, MPC for Android (aarch64-linux-android${ANDROID_API})"

# Resolve in-tree symlinks to actual source paths
GMP_SRC=$(readlink -f gcc/gmp)
MPFR_SRC=$(readlink -f gcc/mpfr)
MPC_SRC=$(readlink -f gcc/mpc)

mkdir -p ${ANDROID_PREREQS}

# GMP
mkdir -p ${BUILDPREFIX}/gmp-android
cd ${BUILDPREFIX}/gmp-android
${GMP_SRC}/configure                    \
    --host=aarch64-linux-android        \
    --prefix=${ANDROID_PREREQS}         \
    --enable-static                     \
    --disable-shared                    \
    CC="${NDK_CC}"                       \
    CXX="${NDK_CXX}"                    \
    AR="${NDK_AR}"                      \
    RANLIB="${NDK_RANLIB}"              \
    NM="${NDK_NM}"
make -j${NPROC}
make install
cd ${SRCPREFIX}

# MPFR
mkdir -p ${BUILDPREFIX}/mpfr-android
cd ${BUILDPREFIX}/mpfr-android
${MPFR_SRC}/configure                   \
    --host=aarch64-linux-android        \
    --prefix=${ANDROID_PREREQS}         \
    --with-gmp=${ANDROID_PREREQS}       \
    --enable-static                     \
    --disable-shared                    \
    CC="${NDK_CC}"                       \
    CXX="${NDK_CXX}"                    \
    AR="${NDK_AR}"                       \
    RANLIB="${NDK_RANLIB}"               \
    NM="${NDK_NM}"
make -j${NPROC}
make install
cd ${SRCPREFIX}

# MPC
mkdir -p ${BUILDPREFIX}/mpc-android
cd ${BUILDPREFIX}/mpc-android
${MPC_SRC}/configure                    \
    --host=aarch64-linux-android        \
    --prefix=${ANDROID_PREREQS}         \
    --with-gmp=${ANDROID_PREREQS}       \
    --with-mpfr=${ANDROID_PREREQS}      \
    --enable-static                     \
    --disable-shared                    \
    CC="${NDK_CC}"                       \
    CXX="${NDK_CXX}"                    \
    AR="${NDK_AR}"                       \
    RANLIB="${NDK_RANLIB}"               \
    NM="${NDK_NM}"
make -j${NPROC}
make install
cd ${SRCPREFIX}

# ============================================================
# Phase 3: Android binutils (Canadian cross)
#   --build  = x86_64-linux-gnu
#   --host   = aarch64-linux-android  (runs on Android)
#   --target = riscv64-unknown-elf    (assembles/links RISC-V code)
# ============================================================
echo "[+] Phase 3: Android binutils (Canadian cross)"

# Need a fresh clone since Phase 1 left binutils-gdb checked out for GDB step
# in the original script. The directory should still be present from Phase 1.
mkdir -p ${BUILDPREFIX}/binutils-android
cd ${BUILDPREFIX}/binutils-android

CFLAGS="-O2 -Wno-error=implicit-function-declaration"    \
CXXFLAGS="-O2 -Wno-error=implicit-function-declaration"  \
../../binutils-gdb/configure                             \
    --build=x86_64-linux-gnu                             \
    --host=aarch64-linux-android                         \
    --target=riscv64-unknown-elf                         \
    --prefix=${INSTALLPREFIX}                            \
    --disable-werror                                     \
    --disable-gdb                                        \
    --disable-sim                                        \
    --disable-libdecnumber                               \
    --disable-readline                                   \
    CC="${NDK_CC}"                                       \
    CXX="${NDK_CXX}"                                     \
    AR="${NDK_AR}"                                       \
    RANLIB="${NDK_RANLIB}"                               \
    NM="${NDK_NM}"                                       \
    STRIP="${NDK_STRIP}"                                 \
    CC_FOR_BUILD="cc"                                    \
    AR_FOR_BUILD="ar"                                    \
    RANLIB_FOR_BUILD="ranlib"                            \
    ${EXTRA_OPTS}                                        \
    ${EXTRA_BINUTILS_OPTS}
make -j${NPROC}
make install
cd ${SRCPREFIX}

# ============================================================
# Phase 4: Android GCC (Canadian cross)
#   --build  = x86_64-linux-gnu
#   --host   = aarch64-linux-android  (the gcc binary runs on Android)
#   --target = riscv64-unknown-elf    (gcc compiles RISC-V code)
#
# Sysroot (headers + libs for riscv64-unknown-elf) comes from Phase 1 native install.
# GMP/MPFR/MPC come from Phase 2 Android-compiled static libs.
# CC_FOR_BUILD points to the native GCC from Phase 1 for internal code generators.
# ============================================================
echo "[+] Phase 4: Android GCC (Canadian cross, C + C++, riscv64-unknown-elf)"

# Make the Phase 1 binaries available on PATH for build-side tools
export PATH="${NATIVE_INSTALL}/bin:${PATH}"

mkdir -p ${BUILDPREFIX}/gcc-android
cd ${BUILDPREFIX}/gcc-android

../../gcc/configure                                             \
    --build=x86_64-linux-gnu                                    \
    --host=aarch64-linux-android                                \
    --target=riscv64-unknown-elf                                \
    --prefix=${INSTALLPREFIX}                                   \
    --with-sysroot=${INSTALLPREFIX}/riscv64-unknown-elf         \
    --with-native-system-header-dir=/include                    \
    --with-newlib                                               \
    --with-gmp=${ANDROID_PREREQS}                               \
    --with-mpfr=${ANDROID_PREREQS}                              \
    --with-mpc=${ANDROID_PREREQS}                               \
    --enable-languages=c,c++                                    \
    --enable-tls                                                \
    --disable-shared                                            \
    --disable-werror                                            \
    --disable-libmudflap                                        \
    --disable-libssp                                            \
    --disable-quadmath                                          \
    --disable-libgomp                                           \
    --disable-nls                                               \
    --disable-bootstrap                                         \
    --without-isl                                               \
    --enable-host-pie                                           \
    --enable-multilib                                           \
    --with-multilib-generator="${MULTILIB_GENERATOR}"           \
    --with-arch=${DEFAULTARCH}                                  \
    --with-abi=${DEFAULTABI}                                    \
    CC="${NDK_CC}"                                              \
    CXX="${NDK_CXX}"                                            \
    AR="${NDK_AR}"                                              \
    RANLIB="${NDK_RANLIB}"                                      \
    NM="${NDK_NM}"                                              \
    STRIP="${NDK_STRIP}"                                        \
    CC_FOR_BUILD="cc"                                           \
    CXX_FOR_BUILD="c++"                                         \
    AR_FOR_BUILD="ar"                                           \
    RANLIB_FOR_BUILD="ranlib"                                   \
    CFLAGS_FOR_TARGET="-O2 -mcmodel=medany"                     \
    CXXFLAGS_FOR_TARGET="-O2 -mcmodel=medany"                   \
    LDFLAGS="-static-libstdc++"                                 \
    ${EXTRA_OPTS}                                               \
    ${EXTRA_GCC_OPTS}
make -j${NPROC}
make install
cd ${SRCPREFIX}

# Copy the newlib sysroot (headers + libs) from the native install into the
# Android install so the Android GCC finds its runtime libraries on-device.
echo "[+] Copying newlib sysroot to Android install"
rsync -a --exclude=bin/ ${NATIVE_INSTALL}/riscv64-unknown-elf/ ${INSTALLPREFIX}/riscv64-unknown-elf/
for tool in as ld ld.bfd ar nm objcopy objdump ranlib readelf strip; do
    src=${INSTALLPREFIX}/bin/riscv64-unknown-elf-${tool}
    dst=${INSTALLPREFIX}/riscv64-unknown-elf/bin/${tool}
    [ -f $src ] && cp $src $dst
done

# Save version info
echo "[+] Saving variables to toolchain directory"
cp versions.sh ${INSTALLPREFIX}/VERSION-gcc
source util/semver-from-git.sh >> ${INSTALLPREFIX}/VERSION-gcc

echo ""
echo "[+] Done!"
echo "[+] Android GCC toolchain installed to: ${INSTALLPREFIX}"
echo "[+] Binaries run on:  aarch64-linux-android${ANDROID_API} (arm64-v8a)"
echo "[+] Toolchain target: riscv64-unknown-elf"
echo ""
echo "[+] To use on device, push ${INSTALLPREFIX} to Android and invoke:"
echo "    ./riscv64-unknown-elf-gcc <sources>"
