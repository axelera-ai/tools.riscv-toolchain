#!/bin/bash -xe

INSTALLPREFIX="${PWD}/install"
BUILDPREFIX=${PWD}/build
SRCPREFIX=${PWD}
MULTILIB_GENERATOR="rv64i-lp64--c rv64ia-lp64--m rv64im-lp64--c rv64if-lp64f-rv64ifd-c rv64iaf-lp64f-rv64imaf,rv64iafc-d rv64imf-lp64f-rv64imfd-c rv64iac-lp64-- rv64imac-lp64-- rv64imafc-lp64f-rv64imafdc- rv64ifd-lp64d--m,c rv64iafd-lp64d-rv64imafd,rv64iafdc- rv64imafdc-lp64d--"

source ./versions.sh
source ./util/util.sh

# Save variables to a file
echo "[+] Saving variables to toolchain directory"
mkdir -p ${INSTALLPREFIX}
cp versions.sh ${INSTALLPREFIX}/VERSION-llvm

download_prerequisites_binutils() {
  # Download libgmp and libmpfr
  download_and_extract "gmp" "${LIBGMP_VERS}" "https://ftp.gnu.org/gnu/gmp/gmp"
  download_and_extract "mpfr" "${LIBMPFR_VERS}" "https://ftp.gnu.org/gnu/mpfr/mpfr"
}


# Build binutils
clone_if_not_exists ${BINUTILS_BRANCH} https://gnu.googlesource.com/binutils-gdb
mkdir -p ${BUILDPREFIX}/binutils-gdb
cd ${BUILDPREFIX}/binutils-gdb

CFLAGS="-O2 -Wno-error=implicit-function-declaration"   \
CXXFLAGS="-O2 -Wno-error=implicit-function-declaration" \
../../binutils-gdb/configure                            \
    --target=riscv64-unknown-elf                        \
    --prefix=${INSTALLPREFIX}                           \
    --with-expat                                        \
    --disable-werror                                    \
    --disable-gdb                                       \
    --disable-sim                                       \
    --disable-libdecnumber                              \
    --disable-readline                                  \
    ${EXTRA_OPTS}                                       \
    ${EXTRA_BINUTILS_OPTS}
make -j${NPROC}
make install
cd ../..
rm -rf binutils-gdb

# Build GDB
clone_if_not_exists ${GDB_BRANCH} https://gnu.googlesource.com/binutils-gdb

cd binutils-gdb
download_prerequisites_binutils
cd ..

mkdir -p ${BUILDPREFIX}/binutils-gdb
cd ${BUILDPREFIX}/binutils-gdb

CFLAGS="-O2 -Wno-error=implicit-function-declaration"   \
CXXFLAGS="-O2 -Wno-error=implicit-function-declaration" \
../../binutils-gdb/configure                            \
    --target=riscv64-unknown-elf                        \
    --prefix=${INSTALLPREFIX}                           \
    --with-expat                                        \
    --disable-werror                                    \
    --enable-gdb                                        \
    --enable-tui                                        \
    --disable-gas                                       \
    --disable-binutils                                  \
    --disable-ld                                        \
    --disable-gold                                      \
    --disable-gprof                                     \
    ${EXTRA_OPTS}                                       \
    ${EXTRA_BINUTILS_OPTS}
make -j${NPROC}
make install
cd ../..
rm -rf binutils-gdb

# Build GCC Stage 1 (w/o standard headers)
clone_if_not_exists ${GCC_BRANCH} https://gnu.googlesource.com/gcc
cd ${SRCPREFIX}/gcc
./contrib/download_prerequisites
mkdir -p ${BUILDPREFIX}/gcc-stage1
cd ${BUILDPREFIX}/gcc-stage1
../../gcc/configure                                     \
    --target=riscv64-unknown-elf                        \
    --prefix=${INSTALLPREFIX}                           \
    --with-sysroot=${INSTALLPREFIX}/riscv64-unknown-elf \
    --with-newlib                                       \
    --without-headers                                   \
    --disable-shared                                    \
    --enable-languages=c                                \
    --disable-werror                                    \
    --disable-libatomic                                 \
    --disable-libmudflap                                \
    --disable-libssp                                    \
    --disable-quadmath                                  \
    --disable-libgomp                                   \
    --disable-nls                                       \
    --disable-bootstrap                                 \
    --enable-multilib                                   \
    --with-multilib-generator="${MULTILIB_GENERATOR}"   \
    --with-arch=${DEFAULTARCH}                          \
    --with-abi=${DEFAULTABI}                            \
    CFLAGS_FOR_TARGET="-O2 -mcmodel=medany"             \
    CXXFLAGS_FOR_TARGET="-O2 -mcmodel=medany"           \
    ${EXTRA_OPTS}                                       \
    ${EXTRA_GCC_OPTS}
make -j${NPROC}
make install
cd ../..

# Build newlib
clone_if_not_exists ${NEWLIB_BRANCH} https://cygwin.com/git/newlib-cygwin.git newlib

PATH=${INSTALLPREFIX}/bin:${PATH}
mkdir -p ${BUILDPREFIX}/newlib
cd ${BUILDPREFIX}/newlib
# The `-Wno-error=implicit-function-declaration` flag is needed to build newlib
# with GCC 14. Otherwise the build fails as the long double support doesn't seem
# to be fully implemented for RISC-V and GCC 14 treats implicit functions as
# errors.
CFLAGS_FOR_TARGET="-O2 -mcmodel=medany -Wno-error=implicit-function-declaration" \
CXXFLAGS_FOR_TARGET="-O2 -mcmodel=medany"                                        \
../../newlib/configure                                                           \
    --target=riscv64-unknown-elf                                                 \
    --prefix=${INSTALLPREFIX}                                                    \
    --with-arch=${DEFAULTARCH}                                                   \
    --with-abi=${DEFAULTABI}                                                     \
    --enable-multilib                                                            \
    --enable-newlib-io-long-double                                               \
    --enable-newlib-io-long-long                                                 \
    --enable-newlib-io-c99-formats                                               \
    --enable-newlib-register-fini                                                \
    ${EXTRA_OPTS}                                                                \
    ${EXTRA_NEWLIB_OPTS}
make -j${NPROC}
make install
cd ../..

# GCC stage 2 (w/ standard headers)
cd ${SRCPREFIX}/gcc
./contrib/download_prerequisites
mkdir -p ${BUILDPREFIX}/gcc-stage2
cd ${BUILDPREFIX}/gcc-stage2
../../gcc/configure                                     \
    --target=riscv64-unknown-elf                        \
    --prefix=${INSTALLPREFIX}                           \
    --with-sysroot=${INSTALLPREFIX}/riscv64-unknown-elf \
    --with-native-system-header-dir=/include            \
    --with-newlib                                       \
    --enable-languages=c,c++                            \
    --enable-tls                                        \
    --disable-werror                                    \
    --disable-libmudflap                                \
    --disable-libssp                                    \
    --disable-quadmath                                  \
    --disable-libgomp                                   \
    --disable-nls                                       \
    --enable-multilib                                   \
    --with-multilib-generator="${MULTILIB_GENERATOR}"   \
    --with-arch=${DEFAULTARCH}                          \
    --with-abi=${DEFAULTABI}                            \
    CFLAGS_FOR_TARGET="-O2 -mcmodel=medany"             \
    CXXFLAGS_FOR_TARGET="-O2 -mcmodel=medany"           \
    ${EXTRA_OPTS}                                       \
    ${EXTRA_GCC_OPTS}
make -j${NPROC}
make install
cd ../..

# Save variables to a file
echo "[+] Saving variables to toolchain directory"
cp versions.sh ${INSTALLPREFIX}/VERSION-gcc

source util/semver-from-git.sh >> ${INSTALLPREFIX}/VERSION-gcc
