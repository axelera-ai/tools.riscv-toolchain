#!/bin/bash -xe

INSTALLPREFIX="${PWD}/install-gnu"
BUILDPREFIX=${PWD}/build-gnu
SRCPREFIX=${PWD}
DEFAULTARCH=rv64imafdc
DEFAULTABI=lp64d
MULTILIB_FLAGS="--enable-multilib"
GLIBC_MULTILIB_NAMES=(
  "rv32imac-ilp32"
  "rv32imafdc-ilp32d"
  "rv64imac-lp64"
  "rv64imafdc-lp64d"
)
SYSROOT=${INSTALLPREFIX}/sysroot
TARGET_TRIPLE=riscv64-unknown-linux-gnu
PATH=${INSTALLPREFIX}/bin:${PATH}

source ./versions.sh
source util/common.sh

########################
# Build stage1 toolchain
########################

source ./build_toolchain_linux_stage1.sh

########################
# Install glibc headers
########################
clone_if_not_exists ${GLIBC_BRANCH} https://github.com/bminor/glibc.git glibc
mkdir -p ${BUILDPREFIX}/glibc
cd ${BUILDPREFIX}/glibc

CFLAGS="-O2 -mcmodel=medany"                        \
CC="${TARGET_TRIPLE}-gcc"                           \
../../glibc/configure                               \
  --host=${TARGET_TRIPLE}                           \
  --prefix=${SYSROOT}/usr                           \
  --enable-shared                                   \
  --with-headers=${SRCPREFIX}/linux-headers/include \
  --with-abi=${ABI}                                 \
  --with-arch=${ARCH}                               \
  ${MULTILIB_FLAGS}
make install-headers
cd ../..

##############
# Build `libc`
##############
# Loop through each multilib target and build GLIBC
for TARGET in "${GLIBC_MULTILIB_NAMES[@]}"; do
  clone_if_not_exists ${GLIBC_BRANCH} https://github.com/bminor/glibc.git glibc-${TARGET}
  # Extract architecture and ABI
  ARCH=$(echo "$TARGET" | cut -d- -f1)
  ABI=$(echo "$TARGET" | cut -d- -f2)
  XLEN=$(echo "$TARGET" | sed -n 's/.*rv\([0-9]*\).*/\1/p')
  # Determine library directory suffix and XLEN
  TARGET_CFLAGS="-march=$ARCH -mabi=$ABI"

  # Buld glibc Linux headers
  echo "[+] Building GLIBC for target: $TARGET"

  mkdir -p ${BUILDPREFIX}/glibc-${TARGET}
  cd ${BUILDPREFIX}/glibc-${TARGET}

	CC="${TARGET_TRIPLE}-gcc ${TARGET_CFLAGS}" \
	CXX="this-is-not-the-compiler-youre-looking-for"    \
	CFLAGS="-mcmodel=medany -O2 ${TARGET_CFLAGS}"       \
	CXXFLAGS="-mcmodel=medany -O2 ${TARGET_CFLAGS}"     \
	ASFLAGS="-mcmodel=medany ${TARGET_CFLAGS}"          \
  ../../glibc-${TARGET}/configure                     \
	--host=riscv${XLEN}-unknown-linux-gnu               \
	--prefix=/usr                                       \
	--disable-werror                                    \
	--enable-shared                                     \
	--enable-obsolete-rpc                               \
	--with-headers=${SRCPREFIX}/linux-headers/include   \
	${MULTILIB_FLAGS}                                   \
	--enable-kernel=3.0.0                               \
	--libdir=/usr/lib${XLEN}/${ABI} libc_cv_slibdir=/lib${XLEN}/${ABI} libc_cv_rtlddir=/lib

  make
  make install install_root=${SYSROOT}
  cd ../..
done

####################################
# GCC stage 2 (w/ standard headers)
####################################
cd ${SRCPREFIX}/gcc
mkdir -p ${BUILDPREFIX}/gcc-stage2
cd ${BUILDPREFIX}/gcc-stage2
../../gcc/configure                                     \
    --target=${TARGET_TRIPLE}                           \
    --prefix=${INSTALLPREFIX}                           \
    --with-sysroot=${SYSROOT}                           \
    --with-system-zlib                                  \
    --enable-shared                                     \
    --enable-tls                                        \
    --enable-languages=c,c++,fortran                    \
    --disable-libmudflap                                \
    --disable-libssp                                    \
    --disable-libquadmath                               \
    --disable-nls                                       \
    --disable-bootstrap                                 \
    --enable-default-pie                                \
    ${MULTILIB_FLAGS}                                   \
    --with-arch=${DEFAULTARCH}                          \
    --with-abi=${DEFAULTABI}                            \
    CFLAGS_FOR_TARGET="-O2 -mcmodel=medany"             \
    CXXFLAGS_FOR_TARGET="-O2 -mcmodel=medany"           \
    ${EXTRA_OPTS}                                       \
    ${EXTRA_GCC_OPTS}
make -j${NPROC}
make install
cp -a ${INSTALLPREFIX}/${TARGET_TRIPLE}/lib* ${SYSROOT}
cd ../..

# Save variables to a file
echo "[+] Saving variables to toolchain directory"
cp versions.sh ${INSTALLPREFIX}/VERSION

source util/semver-from-git.sh >> ${INSTALLPREFIX}/VERSION
