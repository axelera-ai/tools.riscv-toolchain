
#################
# Build binutils
#################
clone_if_not_exists ${BINUTILS_BRANCH} https://gnu.googlesource.com/binutils-gdb
rm -rf ${BUILDPREFIX}/binutils-gdb
mkdir -p ${BUILDPREFIX}/binutils-gdb
cd ${BUILDPREFIX}/binutils-gdb

CFLAGS="-O2 -Wno-error=implicit-function-declaration"   \
CXXFLAGS="-O2 -Wno-error=implicit-function-declaration" \
../../binutils-gdb/configure                            \
    --target=${TARGET_TRIPLE}                           \
    --prefix=${INSTALLPREFIX}                           \
    --with-sysroot=${SYSROOT}                           \
    --enable-plugins                                    \
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

# Install Linux Header
mkdir -p ${SYSROOT}/usr/
cp -a ${SRCPREFIX}/linux-headers/include ${SYSROOT}/usr/


###########################################
# Build GCC Stage 1 (w/o standard headers)
###########################################
clone_if_not_exists ${GCC_BRANCH} https://gnu.googlesource.com/gcc
cd ${SRCPREFIX}/gcc
./contrib/download_prerequisites
mkdir -p ${BUILDPREFIX}/gcc-stage1
cd ${BUILDPREFIX}/gcc-stage1
../../gcc/configure                                   \
    --target=${TARGET_TRIPLE}                         \
    --prefix=${INSTALLPREFIX}                         \
    --with-sysroot=${SYSROOT}                         \
    --with-newlib                                     \
    --without-headers                                 \
    --disable-shared                                  \
    --disable-threads                                 \
    --enable-tls                                      \
    --enable-languages=c                              \
    --disable-libatomic                               \
    --disable-libmudflap                              \
    --disable-libssp                                  \
    --disable-libquadmath                             \
    --disable-libgomp                                 \
    --disable-nls                                     \
    --disable-bootstrap                               \
    ${MULTILIB_FLAGS}                                 \
    --with-arch=${DEFAULTARCH}                        \
    --with-abi=${DEFAULTABI}                          \
    CFLAGS_FOR_TARGET="-O2 -mcmodel=medany"           \
    CXXFLAGS_FOR_TARGET="-O2 -mcmodel=medany"         \
    ${EXTRA_OPTS}                                     \
    ${EXTRA_GCC_OPTS}
make inhibit-libc=true all-gcc -j${NPROC}
make inhibit-libc=true install-gcc -j${NPROC}
make inhibit-libc=true all-target-libgcc -j${NPROC}
make inhibit-libc=true install-target-libgcc -j${NPROC}
cd ../..
