#!/bin/bash -xe
# Resume from Phase 4 only — Phases 1-3 already completed.
SRCPREFIX="${PWD}"
BUILDPREFIX="${PWD}/build"
INSTALLPREFIX="${PWD}/install-android-gcc"
NATIVE_INSTALL="${BUILDPREFIX}/native-install"
ANDROID_PREREQS="${BUILDPREFIX}/android-prereqs"
MULTILIB_GENERATOR="rv64i-lp64--c rv64ia-lp64--m rv64im-lp64--c rv64if-lp64f-rv64ifd-c rv64iaf-lp64f-rv64imaf,rv64iafc-d rv64imf-lp64f-rv64imfd-c rv64iac-lp64-- rv64imac-lp64-- rv64imafc-lp64f-rv64imafdc- rv64ifd-lp64d--m,c rv64iafd-lp64d-rv64imafd,rv64iafdc- rv64imafdc-lp64d--"

source ./versions.sh
source ./util/util.sh

NDK_ROOT="${ANDROID_NDK_HOME:-/home/ubuntu/android-ndk-r23c}"
ANDROID_API=28
TOOLCHAIN="${NDK_ROOT}/toolchains/llvm/prebuilt/linux-x86_64"
NDK_CC="${TOOLCHAIN}/bin/aarch64-linux-android${ANDROID_API}-clang"
NDK_CXX="${TOOLCHAIN}/bin/aarch64-linux-android${ANDROID_API}-clang++"
NDK_AR="${TOOLCHAIN}/bin/llvm-ar"
NDK_RANLIB="${TOOLCHAIN}/bin/llvm-ranlib"
NDK_NM="${TOOLCHAIN}/bin/llvm-nm"
NDK_STRIP="${TOOLCHAIN}/bin/llvm-strip"

export PATH="${NATIVE_INSTALL}/bin:${PATH}"

echo "[+] Phase 4: Android GCC (Canadian cross, --without-isl)"
rm -rf "${BUILDPREFIX}/gcc-android"
mkdir -p "${BUILDPREFIX}/gcc-android"
cd "${BUILDPREFIX}/gcc-android"

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
    "--with-multilib-generator=${MULTILIB_GENERATOR}"           \
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

echo "[+] Copying newlib sysroot to Android install"
rsync -a ${NATIVE_INSTALL}/riscv64-unknown-elf/ ${INSTALLPREFIX}/riscv64-unknown-elf/

echo "[+] Done! Android GCC installed to: ${INSTALLPREFIX}"
