#!/bin/bash -xe

INSTALLPREFIX="${PWD}/install-musl"
BUILDPREFIX=${PWD}/build-musl
SRCPREFIX=${PWD}
DEFAULTARCH=rv64imafdc
DEFAULTABI=lp64d
MULTILIB_FLAGS="--disable-multilib"
SYSROOT=${INSTALLPREFIX}/sysroot
TARGET_TRIPLE=riscv64-unknown-linux-musl
PATH=${INSTALLPREFIX}/bin:${PATH}

source ./versions.sh
source util/common.sh

########################
# Build stage1 toolchain
########################

source ./build_toolchain_linux_stage1.sh

###########################
# Build musl linux headers
###########################
wget https://musl.libc.org/releases/musl-${MUSL_VERS}.tar.gz
tar xvf musl-${MUSL_VERS}.tar.gz
rm musl-${MUSL_VERS}.tar.gz
mkdir -p ${BUILDPREFIX}/musl
cd ${BUILDPREFIX}/musl

CC="${TARGET_TRIPLE}-gcc"                           \
../../musl-${MUSL_VERS}/configure                   \
  --host=${TARGET_TRIPLE}                           \
  --prefix=${SYSROOT}/usr                           \
  --disabled-shared                                 \
  --with-headers=${SRCPREFIX}/linux-headers/include \
  --disable-multilib                                \
  --enable-kernel=3.0.0
make install-headers
cd ../..

############
# Build musl
############
cd ${BUILDPREFIX}/musl
CC="${TARGET_TRIPLE}-gcc"         \
CXX="${TARGET_TRIPLE}-g++"        \
CFLAGS="-O2 -mcmodel=medany"      \
CXXFLAGS="-O2 -mcmodel=medany"    \
ASFLAGS="-mcmodel=medany"         \
../../musl-${MUSL_VERS}/configure \
  --host=${TARGET_TRIPLE}         \
  --prefix=${SYSROOT}
make -j${NPROC}
make install

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
    --disable-shared                                    \
    --enable-tls                                        \
    --enable-languages=c,c++,fortran                    \
    --disable-libmudflap                                \
    --disable-libssp                                    \
    --disable-libquadmath                               \
    --disable-nls                                       \
    --disable-bootstrap                                 \
    --with-arch=${DEFAULTARCH}                          \
    --with-abi=${DEFAULTABI}                            \
    --disable-multilib                                  \
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
