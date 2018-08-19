#!/usr/bin/env sh

REMOTEUSER=pi       # Remote login for root not allowed in default settings
REMOTEIP=lewis_pi   # Remote machine is in a VirtualBox on localhost
REMOTEPORT=22       # VirtualBox might require port forwarding on localhost

# ^^^ DEFINITELY CONFIGURE THE ABOVE ^^^

PREFIX=`pwd`/crossrust
TOOLCHAIN=${PREFIX}/toolchain
SYSROOT=${PREFIX}/sysroot_mount
BUILD=${PREFIX}/build
DOWNLOAD=`pwd`/download
LOG=${PREFIX}/build.log
NCPUS=`grep -m 1 'cpu cores' /proc/cpuinfo | awk '{print $4}'` # `sysctl -n hw.ncpu`
GCCMAJOR=7
BINUTILSVERSION=2.31
MPFRVERSION=4.0.1
MPCVERSION=1.1.0
GMPVERSION=6.1.2

# ^^^ TWEAK ABOVE IF NEEDED ^^^

RUST_TARGET_TRIPLET=arm-unknown-linux-gnueabihf
GCC_TARGET_TRIPLET=${RUST_TARGET_TRIPLET} #arm-linux-gnueabihf

export CC=/usr/bin/gcc-${GCCMAJOR}
export CXX=/usr/bin/g++-${GCCMAJOR}
export CPP=/usr/bin/cpp-${GCCMAJOR}
export LD=/usr/bin/gcc-${GCCMAJOR}

if [ ! -d ${PREFIX} ]
then
    echo "===> Creating dir ${PREFIX}"
    mkdir -p ${PREFIX} || (echo "mkdir -p ${PREFIX} failed. Trying with sudo." && sudo mkdir -p ${PREFIX} && sudo chown ${USER} ${PREFIX} || exit 1)
fi
mkdir -p ${BUILD} || exit 1
mkdir -p ${TOOLCHAIN} || exit 1
mkdir -p ${SYSROOT} || exit 1
mkdir -p ${DOWNLOAD} || exit 1

touch ${LOG}
echo Starting log > ${LOG}


rsync --version >> ${LOG} && echo "===> Found rsync" || (echo "Please install rsync" && exit 1)
ssh -p ${REMOTEPORT} ${REMOTEUSER}@${REMOTEIP} rsync --version >> ${LOG}  && echo "===> Found remote rsync"  || (echo "Please install rsync on remote machine" && exit 1)

${CC} --version >> ${LOG} && echo "===> Found ${CC}" || (echo "${CC} not found" && exit 1)
GCCVERSION=`${CC} --version | head -n 1 | awk '{print $4}'`


echo "===> Mounting remote root with sshfs as sysroot at ${SYSROOT}"
sshfs -p ${REMOTEPORT} -o idmap=user,follow_symlinks ${REMOTEUSER}@${REMOTEIP}:/ ${SYSROOT} || exit 1

#
# Download tarballs
#

BINUTILS_NAME=binutils-${BINUTILSVERSION}
MPFR_NAME=mpfr-${MPFRVERSION}
MPC_NAME=mpc-${MPCVERSION}
GMP_NAME=gmp-${GMPVERSION}
GCC_NAME=gcc-${GCCVERSION}

if [ ! -f ${PREFIX}/.fetch ]
then
    echo "===> Fetching tarballs"
    cd ${DOWNLOAD}
    wget -c http://ftp.gnu.org/gnu/binutils/${BINUTILS_NAME}.tar.gz || exit 1
    wget -c http://ftp.gnu.org/gnu/mpfr/${MPFR_NAME}.zip || exit 1
    wget -c http://ftp.gnu.org/gnu/mpc/${MPC_NAME}.tar.gz || exit 1
    wget -c http://ftp.gnu.org/gnu/gmp/${GMP_NAME}.tar.xz || exit 1
    wget -c http://ftp.gnu.org/gnu/gcc/${GCC_NAME}/${GCC_NAME}.tar.gz || exit 1
    touch ${PREFIX}/.fetch
else
    echo "===> Skipping fetch tarballs"
fi


#
# Extract tarballs
#
if [ ! -f ${PREFIX}/.extract ]
then
    echo "===> Extracting tarballs"
    cd ${BUILD}
    tar xf ${DOWNLOAD}/${BINUTILS_NAME}.tar.gz || exit 1
    unzip -q ${DOWNLOAD}/${MPFR_NAME}.zip || exit 1
    tar xf ${DOWNLOAD}/${MPC_NAME}.tar.gz || exit 1
    tar xf ${DOWNLOAD}/${GMP_NAME}.tar.xz || exit 1
    tar xf ${DOWNLOAD}/${GCC_NAME}.tar.gz || exit 1
    touch ${PREFIX}/.extract
else
    echo "===> Skipping extract tarballs"
fi


#
# Build binutils
#
if [ ! -f ${PREFIX}/.binutils ]
then
    echo "===> Building binutils"
    cd ${BUILD}
    mkdir -p build-binutils || exit 1
    cd build-binutils
    ../${BINUTILS_NAME}/configure --prefix=${TOOLCHAIN} --target=${GCC_TARGET_TRIPLET} --with-sysroot=${SYSROOT} \
		--enable-interwork --enable-multilib --disable-nls --disable-werror || exit 1
    make -j${NCPUS} || exit 1
    make install || exit 1
    touch ${PREFIX}/.binutils
else
    echo "===> Skipping binutils"
fi



#
# GCC
#
# Link in libraries so they will be built together with gcc.

MPFR_SRC=${BUILD}/${MPFR_NAME}
MPC_SRC=${BUILD}/${MPC_NAME}
GMP_SRC=${BUILD}/${GMP_NAME}

MPFR_DEST=${BUILD}/${GCC_NAME}/mpfr
MPC_DEST=${BUILD}/${GCC_NAME}/mpc
GMP_DEST=${BUILD}/${GCC_NAME}/gmp

cd ${BUILD}
ln -sf ${MPFR_SRC} ${MPFR_DEST} || exit 1
ln -sf ${MPC_SRC} ${MPC_DEST} || exit 1
ln -sf ${GMP_SRC} ${GMP_DEST} || exit 1

# MPFR_NAME: mpfr-4.0.1
# MPC_NAME: mpc-1.1.0
# GMP_NAME: gmp-6.1.2
# CWD: /home/armstrong/builder/crossrust/build
# GCC_NAME:/mpfr gcc-7.2.0/mpfr
# GCC_NAME:/mpc gcc-7.2.0/mpc
# GCC_NAME:/gmp gcc-7.2.0/gmp
# PREFIX: /home/armstrong/builder/crossrust
# BUILD: /home/armstrong/builder/crossrust/build

# Build GCC
if [ ! -f ${PREFIX}/.buildgcc ]
then
    echo "===> Building gcc"
    cd ${BUILD}
    rm -fr build-gcc > /dev/null
    mkdir -p build-gcc || exit 1
    cd build-gcc

    ../${GCC_NAME}/configure --prefix=${TOOLCHAIN} --target=${GCC_TARGET_TRIPLET} --with-sysroot=${SYSROOT} \
    --with-arch=armv6 --with-fpu=vfp --with-float=hard --disable-multilib \
    || exit 1

	   # --disable-nls --enable-languages=c,c++ --without-headers --enable-multilib \ 

    make -j${NCPUS} || exit 1
    make install || exit 1
    touch ${PREFIX}/.buildgcc
else
    echo "===> Skipping build gcc"
fi

unset CC
unset CXX
unset CPP
unset LD

#
# Rust
#
rustup -V >> ${LOG} && echo "===> Found rustup" || (echo "Please install rustup" && exit 1)


# Download toolchain
if [ ! -f ${PREFIX}/.rustup ]
then
    echo "===> Installing rust toolchains"
    rustup toolchain install nightly
    rustup target add ${RUST_TARGET_TRIPLET} || exit 1
    rustup toolchain install nightly-${RUST_TARGET_TRIPLET} || exit 1
    touch ${PREFIX}/.rustup
else
    echo "===> Skipping install rust toolchains"
fi

# Set linker
if [ ! -f ${PREFIX}/.linker ]
then
    echo "===> Setting Cargo linker"
    cd ${PREFIX}
    mkdir -p .cargo || exit 1
    cat <<EOF > .cargo/config
[target.${RUST_TARGET_TRIPLET}]
linker = "${TOOLCHAIN}/bin/${RUST_TARGET_TRIPLET}-gcc"
EOF
    touch ${PREFIX}/.linker
else
    echo "===> Skipping set Cargo linker"
fi

# Create and build hello world crate
cd ${PREFIX}
if [ ! -f ${PREFIX}/.helloworld ]
then
    echo "===> Building rust hello world crate"
    rm -fr helloworld > /dev/null
    cargo new --bin helloworld || exit 1
    cd helloworld
    rustup override set nightly || exit 1

    cargo build --target ${RUST_TARGET_TRIPLET} || exit 1
    file target/${RUST_TARGET_TRIPLET}/debug/helloworld | grep -q ${RUST_TARGET_TRIPLET} && echo "Successfully cross compiled ARM binary" || (echo "Something is wrong the the compiled rust binary" && exit 1)
    touch ${PREFIX}/.helloworld
else
    echo "===> Skipping build rust hello world crate"
fi


echo "===> Unmounting sysroot"
sudo umount ${SYSROOT}

#
# Run on remote machine
#
echo "===> Copy binary to remote machine"
scp -P ${REMOTEPORT} ${PREFIX}/helloworld/target/${RUST_TARGET_TRIPLET}/debug/helloworld ${REMOTEUSER}@${REMOTEIP}:/tmp/helloworld  > /dev/null || exit 1

echo "===> Executing binary on remote ARM machine. Expected output is \"Hello, world!\", actual output is: "
ssh -p ${REMOTEPORT} ${REMOTEUSER}@${REMOTEIP} /tmp/helloworld
