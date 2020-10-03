#!/bin/bash
set -e
set -x
set -o pipefail

ROOT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "${ROOT_DIR}"

export PATH="/usr/lib/ccache/bin:${PATH}"

# Env
# CPU stuff
MKSYSTEM_ARCH=armv8-a+crypto+crc
MKSYSTEM_HOST=$(echo ${MACHTYPE} | sed "s/-[^-]*/-cross/")
MKSYSTEM_TARGET=aarch64-linux-musleabihf
MKSYSTEM_TARGET_CFLAGS="-O3 -march=armv8-a+crc+simd+crypto -mcpu=cortex-a72+crc+simd+crypto"
# Paths
MKSYSTEM_ROOT="${ROOT_DIR}/build"
MKSYSTEM_STATE="${MKSYSTEM_ROOT}/state"
MKSYSTEM_SOURCES="${MKSYSTEM_ROOT}/sources"
MKSYSTEM_CROSS_TOOLS="${MKSYSTEM_ROOT}/cross-tools"
MKSYSTEM_CROSS_TOOLS_TARGET="${MKSYSTEM_CROSS_TOOLS}/${MKSYSTEM_TARGET}"

export PATH="${MKSYSTEM_CROSS_TOOLS}/bin:${MKSYSTEM_CROSS_TOOLS_TARGET}/bin:${PATH}"


# Other
MAKEFLAGS="-j$(nproc)"

# Versions
LINUX_VERSION=5.8.13
BINUTILS_VERSION=2.34.90
GCC_VERSION=10.2.0
MUSL_VERSION=1.2.1


# Misc Functions

function download() {
    if [ ! -f "$(basename "${1}")" ]; then
        aria2c -x4 -s4 "${1}"
    fi
}

function extract() {
    if [ ! -d "${2}" ]; then
        bsdtar xf "${1}"
    fi
}

function markDone() {
    touch "${MKSYSTEM_STATE}/installed/${1}"
}

function isDone() {
    [ -f "${MKSYSTEM_STATE}/installed/${1}" ]
}

# 1. Make all needed folders.

mkdir -p "${MKSYSTEM_ROOT}"
mkdir -p "${MKSYSTEM_STATE}" "${MKSYSTEM_STATE}/installed"
mkdir -p "${MKSYSTEM_SOURCES}"

mkdir -p "${MKSYSTEM_CROSS_TOOLS_TARGET}"
if ! ls "${MKSYSTEM_CROSS_TOOLS_TARGET}/usr"; then
  ln -sfv "${MKSYSTEM_CROSS_TOOLS_TARGET}" "${MKSYSTEM_CROSS_TOOLS_TARGET}/usr"
fi

#--host=aarch64-unknown-linux-gnu --build=aarch64-unknown-linux-gnu --with-arch=armv8-a --enable-fix-cortex-a53-835769 --enable-fix-cortex-a53-843419

# 2. Create the cross compilation tools.


# 2.1. Install the sanitized kernel headers.
if ! isDone "cross-kernel-headers"; then
    pushd "${MKSYSTEM_SOURCES}"
    download "https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-${LINUX_VERSION}.tar.xz" 
    extract "linux-${LINUX_VERSION}.tar.xz" "linux-${LINUX_VERSION}"
    pushd "linux-${LINUX_VERSION}"
    #make mrproper
    #make ARCH="arm64" headers_check
    make ARCH="arm64" INSTALL_HDR_PATH="${MKSYSTEM_CROSS_TOOLS_TARGET}" headers_install
    popd
    popd
    markDone "cross-kernel-headers"
fi

# 2.2. Install cross binutils.

if ! isDone "cross-binutils"; then
    pushd "${MKSYSTEM_SOURCES}"
    download "ftp://sourceware.org/pub/binutils/snapshots/binutils-${BINUTILS_VERSION}.tar.xz" 
    extract "binutils-${BINUTILS_VERSION}.tar.xz" "binutils-${BINUTILS_VERSION}"
    mkdir -p "cross-binutils-build"
    pushd "cross-binutils-build"
    "../binutils-${BINUTILS_VERSION}/configure" \
        --prefix="${MKSYSTEM_CROSS_TOOLS}" \
        --target="${MKSYSTEM_TARGET}" \
        --with-sysroot="${MKSYSTEM_CROSS_TOOLS_TARGET}" \
        --disable-nls \
        --disable-multilib
    make "${MAKEFLAGS}"
    make install "${MAKEFLAGS}"
    popd
    rm -rf "cross-binutils-build"
    popd
    markDone "cross-binutils"
fi

# 2.3 Install cross gcc static.
if ! isDone "cross-gcc-static"; then
    pushd "${MKSYSTEM_SOURCES}"
    download "ftp://ftp.mirrorservice.org/sites/sourceware.org/pub/gcc/releases/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.xz" 
    extract "gcc-${GCC_VERSION}.tar.xz" "gcc-${GCC_VERSION}"
    pushd "gcc-${GCC_VERSION}"
    ./contrib/download_prerequisites
    popd
    mkdir -p "cross-gcc-static-build"
    pushd "cross-gcc-static-build"

    "../gcc-${GCC_VERSION}/configure" \
        --prefix="${MKSYSTEM_CROSS_TOOLS}" \
        --build="${MKSYSTEM_HOST}" \
        --host="${MKSYSTEM_HOST}" \
        --target="${MKSYSTEM_TARGET}" \
        --with-sysroot="${MKSYSTEM_CROSS_TOOLS_TARGET}" \
        --disable-nls \
        --disable-shared \
        --without-headers \
        --with-newlib \
        --disable-decimal-float \
        --disable-libgomp \
        --disable-libmudflap \
        --disable-libssp \
        --disable-libatomic \
        --disable-libquadmath \
        --disable-threads \
        --enable-languages=c \
        --disable-multilib \
        --disable-bootstrap \
        --with-arch=armv8-a+crc+simd+crypto --enable-fix-cortex-a53-835769 --enable-fix-cortex-a53-843419
    make all-gcc all-target-libgcc "${MAKEFLAGS}"
    make install-gcc install-target-libgcc "${MAKEFLAGS}"
    popd
    rm -rf "cross-gcc-static-build"
    popd
    markDone "cross-gcc-static"
fi


# 2.4. Install cross musl.
if ! isDone "cross-musl"; then
    pushd "${MKSYSTEM_SOURCES}"
    download "http://musl.libc.org/releases/musl-${MUSL_VERSION}.tar.gz" 
    extract "musl-${MUSL_VERSION}.tar.gz" "musl-${MUSL_VERSION}"
    pushd "musl-${MUSL_VERSION}"
    ./configure \
        CROSS_COMPILE="${MKSYSTEM_TARGET}-" \
        --prefix=/ \
        --target="${MKSYSTEM_TARGET}"
    make "${MAKEFLAGS}"
    DESTDIR="${MKSYSTEM_CROSS_TOOLS_TARGET}" make install "${MAKEFLAGS}"
    make clean "${MAKEFLAGS}"
    popd
    popd
    markDone "cross-musl"
fi





exit
if ! isDone ""; then
    pushd "${MKSYSTEM_SOURCES}"
    download "" 
    extract "" ""
    pushd ""

    popd
    popd
    markDone ""
fi
