#!/bin/bash
set -e
set -x
set -o pipefail

#shopt -s extglob

ROOT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

export PATH="/usr/lib/ccache/bin:${PATH}"


# Deps for running
# - Docbook-* 
# - Wayland-Scanner
# - xmlto
# - g-ir-scanner (from gobject-introspection)
# - etc
# basically just recursively install all build deps for kde and gnome and sway and youll be fine2



# Env
# CPU stuff
MKSYSTEM_ARCH=armv8-a+crypto+crc
MKSYSTEM_HOST=aarch64
MKSYSTEM_TARGET=aarch64-linux-musl
MKSYSTEM_TARGET_CFLAGS="-Os -march=armv8-a+crc+simd+crypto -mcpu=cortex-a72+crc+simd+crypto -mlittle-endian -Wno-parentheses -Wno-error=redundant-decls"
# Paths
MKSYSTEM_ROOT="${ROOT_DIR}/build"
MKSYSTEM_FILES="${ROOT_DIR}/files"
MKSYSTEM_PREFIX="${MKSYSTEM_ROOT}/prefix"
MKSYSTEM_STATE="${MKSYSTEM_ROOT}/state"
MKSYSTEM_SOURCES="${MKSYSTEM_ROOT}/sources"
MKSYSTEM_CROSS_TOOLS="${MKSYSTEM_ROOT}/cross-tools"
MKSYSTEM_CROSS_TOOLS_TARGET="${MKSYSTEM_CROSS_TOOLS}/${MKSYSTEM_TARGET}"
MKSYSTEM_CCACHE_BIN="${MKSYSTEM_ROOT}/ccachebin"
MKSYSTEM_MISC="${MKSYSTEM_ROOT}/misc"

MKSYSTEM_TARGET_CFLAGS="${MKSYSTEM_TARGET_CFLAGS} -I${MKSYSTEM_PREFIX}/usr/include --sysroot=${MKSYSTEM_PREFIX}"

export PATH="${MKSYSTEM_CCACHE_BIN}:${MKSYSTEM_CROSS_TOOLS}/bin:${MKSYSTEM_CROSS_TOOLS_TARGET}/bin:$HOME/.cargo/bin:${PATH}"
#export PATH="${MKSYSTEM_CROSS_TOOLS}/bin:${MKSYSTEM_CROSS_TOOLS_TARGET}/bin:$HOME/.cargo/bin:${PATH}"

# Other
MAKEFLAGS="-j6"

# Versions
LINUX_VERSION=5.8.13
BINUTILS_VERSION=2.34.90
GCC_VERSION=10.2.0
MUSL_VERSION=1.2.1
BUSYBOX_VERSION=1.32.0
PKGCONF_VERSION=1.7.3
LIBFFI_VERSION=3.3
LIBDRM_VERSION=2.4.102
LIBINPUT_VERSION=1.16.1
MTDEV_VERSION=1.1.6
LIBXKBCOMMON_VERSION=1.0.1
LIBPNG_VERSION=1.6.37
PIXMAN_VERSION=0.40.0
WLROOTS_VERSION=0.11.0
PCRE_VERSION=8.44
PCRE2_VERSION=10.35
GRAPHITE2_VERSION=1.3.14
FREETYPE_VERSION=2.10.2
HARFBUZZ_VERSION=2.7.2
SWAY_VERSION=1.5
XKEYBOARD_CONFIG_VERSION=2.30
UTIL_LINUX_VERSION=2.36
ALSA_LIB_VERSION=1.2.3.2
LIBOGG_VERSION=1.3.4
LIBVORBIS_VERSION=1.3.7
FLAC_VERSION=1.3.3
LIBSNDFILE_VERSION=1.0.28
# VVER

# Misc Functions
source ${ROOT_DIR}/functions.sh

# Make all needed folders.

mkdir -p "${MKSYSTEM_ROOT}"
mkdir -p "${MKSYSTEM_STATE}"
mkdir -p "${MKSYSTEM_SOURCES}"
mkdir -p "${MKSYSTEM_PREFIX}"
mkdir -p "${MKSYSTEM_CCACHE_BIN}"
mkdir -p "${MKSYSTEM_MISC}"

mkdir -p "${MKSYSTEM_CROSS_TOOLS_TARGET}"
if ! ls "${MKSYSTEM_CROSS_TOOLS_TARGET}/usr"; then
	ln -sfv "${MKSYSTEM_CROSS_TOOLS_TARGET}" "${MKSYSTEM_CROSS_TOOLS_TARGET}/usr"
fi

# Create the cross compilation tools.

# Install the sanitized kernel headers.
if ! isDone "cross-kernel-headers"; then
	pushd "${MKSYSTEM_SOURCES}"
		download "https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-${LINUX_VERSION}.tar.xz" 
		extract "linux-${LINUX_VERSION}.tar.xz" "linux-${LINUX_VERSION}"
		pushd "linux-${LINUX_VERSION}"
			make ARCH="arm64" INSTALL_HDR_PATH="${MKSYSTEM_CROSS_TOOLS_TARGET}" headers_install
		popd
	popd
	markDone "cross-kernel-headers"
fi

# Install cross binutils.

if ! isDone "cross-binutils"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "ftp://sourceware.org/pub/binutils/snapshots/binutils-${BINUTILS_VERSION}.tar.xz" 
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

# Install cross gcc static.
if ! isDone "cross-gcc-static"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "ftp://ftp.mirrorservice.org/sites/sourceware.org/pub/gcc/releases/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.xz" 
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
				--with-arch=armv8-a+crc+simd+crypto \
				--enable-fix-cortex-a53-835769 \
				--enable-fix-cortex-a53-843419
			make all-gcc all-target-libgcc "${MAKEFLAGS}"
			make install-gcc install-target-libgcc "${MAKEFLAGS}"
		popd
		rm -rf "cross-gcc-static-build"
	popd
	markDone "cross-gcc-static"
fi

# Make some symlinks for ccache.
if ! isDone "ccache-symlinks"; then
	pushd "${MKSYSTEM_CCACHE_BIN}"
		ln -s /usr/bin/ccache "${MKSYSTEM_TARGET}-gcc"
		ln -s /usr/bin/ccache "${MKSYSTEM_TARGET}-g++"
	popd
	markDone "ccache-symlinks"
fi

# Install cross musl.
if ! isDone "cross-musl"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "http://musl.libc.org/releases/musl-${MUSL_VERSION}.tar.gz" 
		DEST="${MKSYSTEM_CROSS_TOOLS_TARGET}" autotoolsBuild "musl-${MUSL_VERSION}" CROSS_COMPILE="${MKSYSTEM_TARGET}-" --prefix=/ --target="${MKSYSTEM_TARGET}"
	popd
	markDone "cross-musl"
fi

# Install cross gcc.
if ! isDone "cross-gcc"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "ftp://ftp.mirrorservice.org/sites/sourceware.org/pub/gcc/releases/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.xz"
		pushd "gcc-${GCC_VERSION}"
			./contrib/download_prerequisites
		popd
		mkdir -p "cross-gcc-build"
		pushd "cross-gcc-build"
			"../gcc-${GCC_VERSION}/configure" \
				--prefix="${MKSYSTEM_CROSS_TOOLS}" \
				--build="${MKSYSTEM_HOST}" \
				--host="${MKSYSTEM_HOST}" \
				--target="${MKSYSTEM_TARGET}" \
				--with-sysroot="${MKSYSTEM_CROSS_TOOLS_TARGET}" \
				--disable-nls \
				--enable-languages=c,c++ \
				--enable-c99 \
				--enable-long-long \
				--disable-libmudflap \
				--disable-libsanitizer \
				--disable-multilib \
				--disable-bootstrap \
				--with-arch=armv8-a+crc+simd+crypto \
				--enable-fix-cortex-a53-835769 \
				--enable-fix-cortex-a53-843419
			make "${MAKEFLAGS}"
			make install "${MAKEFLAGS}"
		popd
		rm -rf "cross-gcc-build"
	popd
	markDone "cross-gcc"
fi


# Install pkgconf
if ! isDone "pkgconf"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "https://distfiles.dereferenced.org/pkgconf/pkgconf-${PKGCONF_VERSION}.tar.xz"
		 DEST="${MKSYSTEM_CROSS_TOOLS_TARGET}" autotoolsBuild "pkgconf-${PKGCONF_VERSION}" \
			--prefix="/usr" \
			--program-prefix="${MKSYSTEM_TARGET}-" \
			--with-system-libdir="${MKSYSTEM_PREFIX}/usr/lib" \
			--with-system-includedir="${MKSYSTEM_PREFIX}/usr/lib"
		/usr/bin/echo -e "#!/bin/bash\n${MKSYSTEM_TARGET}-pkgconf --define-prefix --prefix-variable=${MKSYSTEM_PREFIX}/usr \$@" > "${MKSYSTEM_MISC}/pkgconf"
		chmod +x "${MKSYSTEM_MISC}/pkgconf"
	popd


	markDone "pkgconf"
fi


# Start setting up the prefix.

# Create paths.
if ! isDone "create-prefix-paths"; then
	pushd "${MKSYSTEM_PREFIX}"
		mkdir -p usr/{bin,include,lib,share,src}
		ln -s usr/bin bin
		ln -s usr/bin sbin
		ln -s bin usr/sbin
		ln -s usr/lib lib
		ln -s usr/lib lib64
		ln -s lib usr/lib64 
		mkdir -p run/{lock,user}
		mkdir -p var/{cache,lib,local,log,opt,spool}
		ln -s ../run var/run
		ln -s ../run/lock var/lock
		mkdir -p {boot,dev,etc,home}
		mkdir -p {mnt,proc,srv,sys}
		install -d -m 0750 root
		install -d -m 1777 {var/,}tmp
		ln -sf ../proc/mounts etc/mtab
		touch var/log/lastlog
		chmod 664 var/log/lastlog
	popd
	markDone "create-prefix-paths"
fi

# Create prefix files.
if ! isDone "create-prefix-files"; then
	pushd "${MKSYSTEM_PREFIX}"
		cp -f "${MKSYSTEM_FILES}/passwd" etc/passwd
		cp -f "${MKSYSTEM_FILES}/group" etc/group
	popd
	markDone "create-prefix-files"
fi

# Copy over the built GCC libs (libgcc, libstdc++, etc)
if ! isDone "copy-gcc-libs"; then
	pushd "${MKSYSTEM_PREFIX}"
		find "${MKSYSTEM_CROSS_TOOLS_TARGET}/lib64/" -maxdepth 1 -exec cp -r {} "lib/" \;
	popd
	markDone "copy-gcc-libs"
fi

if ! isDone "make-unknown-symlinks"; then
	pushd "${MKSYSTEM_CROSS_TOOLS}/bin"
		ln -s "${MKSYSTEM_TARGET}-ld" "aarch64-unknown-linux-musl-ld"
		ln -s "${MKSYSTEM_TARGET}-gcc" "aarch64-unknown-linux-musl-gcc"
		ln -s "${MKSYSTEM_TARGET}-g++" "aarch64-unknown-linux-musl-g++"
	popd
	markDone "make-unknown-symlinks"
fi


# Start installing some basic stuff.


# Create a cross compiler file for meson.
if ! isDone "meson-cross-make"; then
	pushd "${MKSYSTEM_MISC}"
		cat > meson.cross <<EOF
[constants]
common_flags = ['$(echo "${MKSYSTEM_TARGET_CFLAGS}" | sed -r "s/\s+/','/g")']
[binaries]
c = '${MKSYSTEM_TARGET}-gcc'
cpp = '${MKSYSTEM_TARGET}-g++'
ar = '${MKSYSTEM_TARGET}-gcc-ar'
nm = '${MKSYSTEM_TARGET}-nm'
ld = '${MKSYSTEM_TARGET}-gcc'
strip = '${MKSYSTEM_TARGET}-strip'
readelf = '${MKSYSTEM_TARGET}-readelf'
objcopy = '${MKSYSTEM_TARGET}-objcopy'
pkgconfig = '${MKSYSTEM_MISC}/pkgconf'
[properties]
c_args = common_flags + ['-I${MKSYSTEM_PREFIX}/usr/include']
c_link_args = common_flags + ['-L${MKSYSTEM_PREFIX}/usr/lib']
cpp_args = common_flags + ['-I${MKSYSTEM_PREFIX}/usr/include']
cpp_link_args = common_flags + ['-L${MKSYSTEM_PREFIX}/usr/lib']
[host_machine]
system = 'linux'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
EOF
	popd
	markDone "meson-cross-make"
fi

if ! isDone "cross-launcher"; then
	pushd "${MKSYSTEM_MISC}"
		cat > cross-launcher <<EOF
#!/bin/bash
LD_LIBRARY_PATH=${MKSYSTEM_PREFIX}/usr/lib ${MKSYSTEM_PREFIX}/usr/lib/libc.so \$@
EOF
		chmod +x "cross-launcher" 
	popd
	markDone "cross-launcher"
fi


# Install proper final musl.
if ! isDone "final-musl"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "http://musl.libc.org/releases/musl-${MUSL_VERSION}.tar.gz"
		DEST="${MKSYSTEM_PREFIX}" \
		autotoolsBuild "musl-${MUSL_VERSION}" \
			CROSS_COMPILE="${MKSYSTEM_TARGET}-" \
			--prefix="/usr" \
			--target="${MKSYSTEM_TARGET}"
	popd
	ln -sf "${MKSYSTEM_PREFIX}/usr/lib/libc.so" "${MKSYSTEM_PREFIX}/lib/pthread.so"
	ln -sf "${MKSYSTEM_PREFIX}/usr/lib/libc.so" "${MKSYSTEM_PREFIX}/lib/pthread.so.1"
	ln -sf "${MKSYSTEM_PREFIX}/usr/lib/libc.so" "${MKSYSTEM_PREFIX}/lib/pthread.so.0"
	markDone "final-musl"
fi

# Install busybox.
if ! isDone "busybox"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "https://busybox.net/downloads/busybox-${BUSYBOX_VERSION}.tar.bz2"
		pushd "busybox-${BUSYBOX_VERSION}"
			cp "${MKSYSTEM_FILES}/bbconfig" .config
			sed -i 's/\(CONFIG_\)\(.*\)\(INETD\)\(.*\)=y/# \1\2\3\4 is not set/g' .config
			sed -i 's/\(CONFIG_IFPLUGD\)=y/# \1 is not set/' .config
			sed -i 's/\(CONFIG_FEATURE_WTMP\)=y/# \1 is not set/' .config
			sed -i 's/\(CONFIG_FEATURE_UTMP\)=y/# \1 is not set/' .config
			sed -i 's/\(CONFIG_UDPSVD\)=y/# \1 is not set/' .config
			sed -i 's/\(CONFIG_TCPSVD\)=y/# \1 is not set/' .config
			make ARCH="${MKSYSTEM_ARCH}" CROSS_COMPILE="${MKSYSTEM_TARGET}-" "${MAKEFLAGS}"
			make ARCH="${MKSYSTEM_ARCH}" CROSS_COMPILE="${MKSYSTEM_TARGET}-" CONFIG_PREFIX="${MKSYSTEM_PREFIX}" "${MAKEFLAGS}" install
			cp -v "examples/depmod.pl" "${MKSYSTEM_CROSS_TOOLS_TARGET}/bin"
			chmod -v 755 "${MKSYSTEM_CROSS_TOOLS_TARGET}/bin/depmod.pl"
			make clean "${MAKEFLAGS}"
		popd
	popd
	markDone "busybox"
fi

# Install iana-etc for services and protocols naming.
if ! isDone "iana-etc"; then
	pushd "${MKSYSTEM_PREFIX}"
		cp -f "${MKSYSTEM_FILES}/services" etc/services
		cp -f "${MKSYSTEM_FILES}/protocols" etc/protocols
	popd
	markDone "iana-etc"
fi

# Install zlib-ng for zlib/DEFLATE compression.
if ! isDone "zlib-ng"; then
	pushd "${MKSYSTEM_SOURCES}"
		[ ! -d "zlib-ng" ] && git clone --depth=1 "https://github.com/zlib-ng/zlib-ng"
		CC="${MKSYSTEM_TARGET}-gcc" \
		autotoolsBuild "zlib-ng" \
			--prefix="/usr" \
			--zlib-compat
	popd
	markDone "zlib-ng"
fi

# install lzo
if ! isDone "lzo"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "http://www.oberhumer.com/opensource/lzo/download/lzo-2.10.tar.gz"
		autotoolsBuild "lzo-2.10" \
			--prefix="/usr" \
			--host="${MKSYSTEM_TARGET}"
	popd
fi

# Install libffi for cross-language calls.
if ! isDone "libffi"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "https://github.com/libffi/libffi/releases/download/v${LIBFFI_VERSION}/libffi-${LIBFFI_VERSION}.tar.gz"
		autotoolsBuild "libffi-${LIBFFI_VERSION}" \
			--prefix="/usr" \
			--host="${MKSYSTEM_TARGET}"
	popd
	markDone "libffi"
fi

# Install libpng.
if ! isDone "libpng"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "https://downloads.sourceforge.net/libpng/libpng-${LIBPNG_VERSION}.tar.xz"
		CC="${MKSYSTEM_TARGET}-gcc ${MKSYSTEM_TARGET_CFLAGS}" \
		autotoolsBuild "libpng-${LIBPNG_VERSION}" \
			--prefix="/usr" \
			--host="${MKSYSTEM_TARGET}"
	popd
	markDone "libpng"
fi

# Install libtiff
if ! isDone "libtiff"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "http://download.osgeo.org/libtiff/tiff-4.1.0.tar.gz"
		cmakeBuild "tiff-4.1.0"
	popd
	markDone "libtiff"
fi

# Install libwebp
if ! isDone "libwebp"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "http://downloads.webmproject.org/releases/webp/libwebp-1.1.0.tar.gz"
		autotoolsBuild "libwebp-1.1.0" \
			--prefix="/usr" \
			--host="${MKSYSTEM_TARGET}" \
			--enable-libwebpmux \
            --enable-libwebpdemux \
            --enable-libwebpdecoder \
            --enable-libwebpextras \
            --enable-swap-16bit-csp \
            --disable-static
	popd
	markDone "libwebp"
fi

if ! isDone "libgpg-error"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "https://www.gnupg.org/ftp/gcrypt/libgpg-error/libgpg-error-1.39.tar.bz2"
		autotoolsBuild "libgpg-error-1.39" \
			--prefix=/usr \
			--host=${MKSYSTEM_TARGET}
	popd
	markDone "libgpg-error"
fi

# depends: libgpg-error
if ! isDone "libgcrypt"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "https://www.gnupg.org/ftp/gcrypt/libgcrypt/libgcrypt-1.8.6.tar.bz2"
		autotoolsBuild "libgcrypt-1.8.6" \
			--prefix=/usr \
			--host=${MKSYSTEM_TARGET}
	popd
	markDone "libgcrypt"
fi

if ! isDone "libressl"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "https://ftp.openbsd.org/pub/OpenBSD/LibreSSL/libressl-3.2.1.tar.gz"
		autotoolsBuild "libressl-3.2.1" \
			--prefix=/usr \
			--host=${MKSYSTEM_TARGET}
	popd
	markDone "libressl"
fi

if ! isDone "libunistring"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "https://ftp.gnu.org/gnu/libunistring/libunistring-0.9.10.tar.xz"
		autotoolsBuild "libunistring-0.9.10" \
			--prefix=/usr \
			--host=${MKSYSTEM_TARGET}
	popd
	markDone "libunistring"
fi

# depends: libunistring
if ! isDone "libidn2"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "https://ftp.gnu.org/gnu/libidn/libidn2-2.3.0.tar.gz"
		autotoolsBuild "libidn2-2.3.0" \
			--prefix=/usr \
			--host=${MKSYSTEM_TARGET}
	popd
	markDone "libidn2"
fi

# depends libidn2
if ! isDone "libpsl"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "https://github.com/rockdaboot/libpsl/releases/download/0.21.1/libpsl-0.21.1.tar.gz"
		autotoolsBuild "libpsl-0.21.1" \
			--prefix=/usr \
			--host=${MKSYSTEM_TARGET}
	popd
	markDone "libpsl"
fi

if ! isDone "nettle"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "https://ftp.gnu.org/gnu/nettle/nettle-3.6.tar.gz"
		CPPFLAGS="${MKSYSTEM_TARGET_CFLAGS}" \
		LDFLAGS="-L${MKSYSTEM_PREFIX}/usr/lib -O0" \
		MKSYSTEM_TARGET_CFLAGS="--sysroot=${MKSYSTEM_PREFIX} -O0" \
		autotoolsBuild "nettle-3.6" \
			--prefix=/usr \
			--host=${MKSYSTEM_TARGET} \
			--disable-openssl \
			--disable-fat
	popd
	markDone "nettle"
fi

if ! isDone "libtasn1"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "https://ftp.gnu.org/gnu/libtasn1/libtasn1-4.16.0.tar.gz"
		autotoolsBuild "libtasn1-4.16.0" \
			--prefix=/usr \
			--host=${MKSYSTEM_TARGET}
	popd
	markDone "libtasn1"
fi

# depends: libtasn1,
if ! isDone "p11-kit"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "https://github.com/p11-glue/p11-kit/releases/download/0.23.21/p11-kit-0.23.21.tar.xz"
		autotoolsBuild "p11-kit-0.23.21" \
			--prefix=/usr \
			--host=${MKSYSTEM_TARGET} \
			--without-systemd
	popd
	markDone "p11-kit"
fi

if ! isDone "gmp"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "https://gmplib.org/download/gmp/gmp-6.2.0.tar.zst"
		autotoolsBuild "gmp-6.2.0" \
			--prefix=/usr \
			--host=${MKSYSTEM_TARGET} \
			--enable-cxx
	popd
	markDone "gmp"
fi

# depends: nettle, p11-kit, gmp
if ! isDone "gnutls"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "https://www.gnupg.org/ftp/gcrypt/gnutls/v3.6/gnutls-3.6.15.tar.xz"
		#NETTLE_LIBS="${MKSYSTEM_TARGET_CFLAGS} -L${MKSYSTEM_PREFIX}/usr/lib -lhogweed -lnettle" \
		PKG_CONFIG=${MKSYSTEM_MISC}/pkgconf \
		PKG_CONFIG_LIBDIR="${MKSYSTEM_PREFIX}/usr/lib" \
		PKG_CONFIG_PATH="${MKSYSTEM_PREFIX}/usr/lib/pkgconfig:${MKSYSTEM_PREFIX}/usr/share/pkgconfig" \
		autotoolsBuild "gnutls-3.6.15" \
			--prefix=/usr \
			--host=${MKSYSTEM_TARGET} \
			--disable-guile \
			--with-default-trust-store-file=/etc/ssl/certs/ca-certificates.crt \
			--without-p11-kit --enable-local-libopts
	popd
	markDone "gnutls"
fi

if ! isDone "icu"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "http://github.com/unicode-org/icu/releases/download/release-67-1/icu4c-67_1-src.tgz" "icu4c-67_1-src.tgz" "icu"
		[ -d "icu-host" ] && rm -rf "icu-host"
		cp -r "icu" "icu-host"
		pushd "icu-host/source"
			./configure --prefix=${MKSYSTEM_MISC}/icu-host
			make "${MAKEFLAGS}"
			make install "${MAKEFLAGS}"
		popd
		pushd "icu"
			autotoolsBuild "source" --prefix=/usr --host=${MKSYSTEM_TARGET} --with-cross-build="${MKSYSTEM_SOURCES}/icu-host/source"
		popd
	popd
	markDone "icu"
fi

# Install wayland.
if ! isDone "wayland"; then
	pushd "${MKSYSTEM_SOURCES}"
		[ ! -d "wayland" ] && git clone --depth=1 "https://github.com/wayland-project/wayland"
		pushd "wayland"
			# We want it to use system wayland-scanner so I don't need to build as many deps for host.
			sed "s/scanner_dep =.*//" -i "src/meson.build" || true
			sed "s/wayland_scanner_for_build = .*/wayland_scanner_for_build = find_program('wayland-scanner')/" -i "src/meson.build" || true
		popd
		mesonBuild "wayland" -Dscanner=false -Ddocumentation=false -Ddtd_validation=false
	popd
	markDone "wayland"
fi

if ! isDone "wayland-protocols"; then
	pushd "${MKSYSTEM_SOURCES}"
		[ ! -d "wayland-protocols" ] && git clone --depth=1 "https://github.com/wayland-project/wayland-protocols"
		autotoolsBuild "wayland-protocols" --prefix="/usr" --host="${MKSYSTEM_TARGET}"
	popd
	markDone "wayland-protocols"
fi

#. Install libdrm
if ! isDone "libdrm"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "https://dri.freedesktop.org/libdrm/libdrm-${LIBDRM_VERSION}.tar.xz"
		pushd "libdrm-${LIBDRM_VERSION}"
			# Or else we get errors for musl #ifs 
			sed "s/libdrm_c_args = warn_c_args.*/libdrm_c_args = '-fvisibility=hidden'/g" -i "meson.build" || true
		popd
		mesonBuild "libdrm-${LIBDRM_VERSION}"
	popd
	markDone "libdrm"
fi

#. Install expat.
if ! isDone "expat"; then
	pushd "${MKSYSTEM_SOURCES}"
		[ ! -d "expat" ] && git clone "https://github.com/libexpat/libexpat"
		autotoolsBuild "libexpat/expat" --prefix="/usr" --host="${MKSYSTEM_TARGET}"
	popd
	markDone "expat"
fi

#. Install mesa!
if ! isDone "mesa"; then
	pushd "${MKSYSTEM_SOURCES}"
		[ ! -d "mesa" ] && git clone --depth=1 "https://gitlab.freedesktop.org/mesa/mesa"
		mesonBuild "mesa" \
			-Degl=enabled -Dgbm=enabled -Ddri3=enabled -Dglx=disabled -Dglvnd=false -D shared-glapi=enabled \
			-Dgles1=enabled -Dgles2=enabled -Dplatforms=wayland \
			-Dgallium-drivers=kmsro,panfrost -Dvulkan-drivers="" -Dlibunwind=false \
			-Dzstd=disabled -Dtools="" -Dshader-cache=disabled
	popd
	markDone "mesa"
fi

#. Install util-linux's libs (libblkid, etc)
if ! isDone "util-linux"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "https://mirrors.edge.kernel.org/pub/linux/utils/util-linux/v${UTIL_LINUX_VERSION}/util-linux-${UTIL_LINUX_VERSION}.tar.xz"
			autotoolsBuild "util-linux-${UTIL_LINUX_VERSION}" \
			--prefix="/usr" \
			--host="${MKSYSTEM_TARGET}" \
			--without-readline \
			--without-systemd \
			--disable-all-programs \
			--disable-nls \
			--enable-libblkid --enable-libmount
	popd
	markDone "util-linux"
fi

#. Install eudev.
if ! isDone "eudev"; then
	pushd "${MKSYSTEM_SOURCES}"
		[ ! -d "eudev" ] && git clone --depth=1 "https://github.com/gentoo/eudev"
		autotoolsBuild "eudev" \
			--prefix="/usr" \
			--host="${MKSYSTEM_TARGET}" \
			--sysconfdir="/etc" \
			--with-rootrundir="/run" \
			--disable-manpages \
			--disable-hwdb --disable-kmod --with-rootprefix="${MKSYSTEM_PREFIX}/usr" --sbindir="${MKSYSTEM_PREFIX}/usr/bin" --bindir="${MKSYSTEM_PREFIX}/usr/bin" --sysconfdir="${MKSYSTEM_PREFIX}/etc" --enable-split-usr
	popd
	markDone "eudev"
fi

#. Install mtdev.
if ! isDone "mtdev"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "http://bitmath.org/code/mtdev/mtdev-${MTDEV_VERSION}.tar.gz"
		pushd "mtdev-${MTDEV_VERSION}"
			# It ships with way outdated autotools files, update needed!
			autoreconf -fi
		popd
		autotoolsBuild "mtdev-${MTDEV_VERSION}" --prefix="/usr" --host="${MKSYSTEM_TARGET}"
	popd
	markDone "mtdev"
fi

#.5. Install libevdev
if ! isDone "libevdev"; then
	pushd "${MKSYSTEM_SOURCES}"
		[ ! -d "libevdev" ] && git clone --depth=1 "https://gitlab.freedesktop.org/libevdev/libevdev.git"
		mesonBuild "libevdev" -Dtests=disabled -Ddocumentation=disabled
	popd
	markDone "libevdev"
fi


#. Install libinput.
if ! isDone "libinput"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "https://www.freedesktop.org/software/libinput/libinput-${LIBINPUT_VERSION}.tar.xz"
		pushd "libinput-${LIBINPUT_VERSION}"
			sed "s/, '-pedantic', '-Werror'//" -i "meson.build" || true
			sed "s/-Werror/-Wno-error/" -i "meson.build" || true
		popd
		mesonBuild "libinput-${LIBINPUT_VERSION}" -Ddocumentation=false -Ddebug-gui=false -Dtests=false -Dlibwacom=false
	popd
	markDone "libinput"
fi

#. Install libxkbcommon.
if ! isDone "libxkbcommon"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "https://xkbcommon.org/download/libxkbcommon-${LIBXKBCOMMON_VERSION}.tar.xz"
		mesonBuild "libxkbcommon-${LIBXKBCOMMON_VERSION}" -Ddefault-layout=gb -Denable-docs=false -Denable-xkbregistry=false -Denable-x11=false
	popd
	markDone "libxkbcommon"
fi

# Install xkeyboard-config
if ! isDone "xkeyboard-config"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "https://www.x.org/pub/individual/data/xkeyboard-config/xkeyboard-config-${XKEYBOARD_CONFIG_VERSION}.tar.bz2"
		autotoolsBuild "xkeyboard-config-${XKEYBOARD_CONFIG_VERSION}" --prefix="/usr" --host="${MKSYSTEM_TARGET}"
	popd
	markDone "xkeyboard-config"
fi


#. Install pixman.
if ! isDone "pixman"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "https://www.cairographics.org/releases/pixman-${PIXMAN_VERSION}.tar.gz"
		pushd "pixman-${PIXMAN_VERSION}"
			sed -e "s/subdir.*test.*//" -e "s/subdir.*demo.*//" -i "meson.build"
		popd
		mesonBuild "pixman-${PIXMAN_VERSION}" -Dlibpng=enabled -Dgtk=disabled
	popd
	markDone "pixman"
fi

#. Install wlroots.
if ! isDone "wlroots"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "https://github.com/swaywm/wlroots/releases/download/${WLROOTS_VERSION}/wlroots-${WLROOTS_VERSION}.tar.gz"
		pushd "wlroots-${WLROOTS_VERSION}"
			sed "s/-Wundef/-Wno-undef/" -i "meson.build"
		popd
		mesonBuild "wlroots-${WLROOTS_VERSION}" -Dxwayland=disabled -Dx11-backend=disabled -Dlogind=disabled -Dexamples=false
	popd
	markDone "wlroots"
fi

#. Install json-c.
if ! isDone "json-c"; then
	pushd "${MKSYSTEM_SOURCES}"
		[ ! -d "json-c" ] && git clone --depth=1 "https://github.com/json-c/json-c.git"
		cmakeBuild "json-c"
	popd
	markDone "json-c"
fi


#. Install PCRE.
if ! isDone "pcre"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "https://ftp.pcre.org/pub/pcre/pcre-${PCRE_VERSION}.tar.gz"
		autotoolsBuild "pcre-${PCRE_VERSION}" --prefix="/usr" --host="${MKSYSTEM_TARGET}"
	popd
	markDone "pcre"
fi

if ! isDone "pcre2"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "https://ftp.pcre.org/pub/pcre/pcre2-${PCRE2_VERSION}.tar.gz"
		autotoolsBuild "pcre2-${PCRE2_VERSION}" --prefix="/usr" --host="${MKSYSTEM_TARGET}"
	popd
	markDone "pcre2"
fi



#. Install glib.
if ! isDone "glib"; then
	pushd "${MKSYSTEM_SOURCES}"
		[ ! -d "glib" ] && git clone --depth=1 "https://gitlab.gnome.org/GNOME/glib"
		pushd "glib"
			#sed "s/gl_cv_func_frexpl_works = false/gl_cv_func_frexpl_works = true/" -i "glib/gnulib/meson.build" || true
			#sed "s/gl_cv_func_frexpl_broken_beyond_repair = true/gl_cv_func_frexpl_broken_beyond_repair = false/" -i "glib/gnulib/meson.build" || true
			#sed "s/not gl_cv_func_frexpl_works and gl_cv_func_frexpl_broken_beyond_repair/false/" -i "glib/gnulib/meson.build" || true
			#sed "s/if build_tests/if false/" -i "meson.build" -i "gio/meson.build" || true
			#sed "s/if build_tests/if false/" -i "meson.build" -i "glib/meson.build" || true
			#sed "s/if not meson.is_cross_build\(\)/if true/" -i "meson.build" || true
			git apply "${MKSYSTEM_FILES}/glib.diff"
		popd
		mesonBuild "glib" -Dman=false -Dgtk_doc=false -Dlibelf=disabled -Dinternal_pcre=true
	popd
	markDone "glib"
fi

# depends: glib
if ! isDone "gobject-introspection"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "http://ftp.gnome.org/pub/gnome/sources/gobject-introspection/1.66/gobject-introspection-1.66.1.tar.xz"
		echo -e "#!/bin/bash\n/usr/bin/g-ir-scanner -L${MKSYSTEM_PREFIX} \$@" > "${MKSYSTEM_MISC}/g-ir-scanner"
		PKG_CONFIG=${MKSYSTEM_MISC}/pkgconf \
		PKG_CONFIG_LIBDIR="${MKSYSTEM_PREFIX}/usr/lib" \
		PKG_CONFIG_PATH="${MKSYSTEM_PREFIX}/usr/lib/pkgconfig:${MKSYSTEM_PREFIX}/usr/share/pkgconfig" \
		PATH="${MKSYSTEM_MISC}:$PATH"
		sed -i 's/typelibs/\[\]/' "gobject-introspection-1.66.1/meson.build"
		mesonBuild "gobject-introspection-1.66.1" \
			-Dgi_cross_use_prebuilt_gi=true -Dbuild_introspection_data=false
	popd
	markDone "gobject-introspection"
fi

# depends: gobject-introspection
if ! isDone "gsettings-desktop-schemas"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "http://ftp.gnome.org/pub/gnome/sources/gsettings-desktop-schemas/3.38/gsettings-desktop-schemas-3.38.0.tar.xz"
		mesonBuild "gsettings-desktop-schemas-3.38.0"
		glib-compile-schemas "${MKSYSTEM_PREFIX}/usr/share/glib-2.0/schemas"
	popd
	markDone "gsettings-desktop-schemas"
fi

# depends: glib, gnutls, gsettings-desktop-schemas
if ! isDone "glib-networking"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "http://ftp.gnome.org/pub/gnome/sources/glib-networking/2.66/glib-networking-2.66.0.tar.xz"
		mesonBuild "glib-networking-2.66.0" -Dlibproxy=disabled 

	popd
	markDone "glib-networking"
fi

if ! isDone "sqlite"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "https://sqlite.org/2020/sqlite-autoconf-3330000.tar.gz"
		SQLITE_CPPFLAGS="${MKSYSTEM_TARGET_CFLAGS} -DSQLITE_ENABLE_COLUMN_METADATA=1 \
                             -DSQLITE_ENABLE_UNLOCK_NOTIFY \
                             -DSQLITE_ENABLE_DBSTAT_VTAB=1 \
                             -DSQLITE_ENABLE_FTS3_TOKENIZER=1 \
                             -DSQLITE_SECURE_DELETE \
                             -DSQLITE_MAX_VARIABLE_NUMBER=250000 \
                             -DSQLITE_MAX_EXPR_DEPTH=10000 \
                             -DSQLITE_DEFAULT_CACHE_SIZE=-1"
		
		CPPFLAGS="${SQLITE_CPPFLAGS}" CFLAGS="${MKSYSTEM_TARGET_CFLAGS}" autotoolsBuild "sqlite-autoconf-3330000" \
			--prefix="/usr" \
			--host="${MKSYSTEM_TARGET}" \
			--enable-fts3
	popd
	markDone "sqlite"
fi

# depends: glib-networking, libpsl, libxml2, sqlite
if ! isDone "libsoup"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "http://ftp.gnome.org/pub/gnome/sources/libsoup/2.72/libsoup-2.72.0.tar.xz"
		sed -i 's/assert.*returncode.*//' "libsoup-2.72.0/meson.build"
		mesonBuild "libsoup-2.72.0" -Dvapi=disabled -Dgssapi=disabled -Dlibproxy=disabled -Dbrotli=disabled -Dgnome=false -Dtests=false -Dsysprof=disabled -Dintrospection=disabled
	popd
	markDone "libsoup"
fi



# Font Stuff.. (there has been circular depends for years at this point ":\(" )
# Graphite2 - Stage0
if ! isDone "graphite-stage0"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "https://github.com/silnrsi/graphite/releases/download/${GRAPHITE2_VERSION}/graphite2-${GRAPHITE2_VERSION}.tgz"
		pushd "graphite2-${GRAPHITE2_VERSION}"
			sed -i "/cmptest/d" "tests/CMakeLists.txt" || true
		popd
		cmakeBuild "graphite2-${GRAPHITE2_VERSION}"
	popd
	markDone "graphite-stage0"
fi

# Freetype - Stage0
if ! isDone "freetype-stage0"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "https://downloads.sourceforge.net/freetype/freetype-${FREETYPE_VERSION}.tar.xz"
		LDFLAGS="-L${MKSYSTEM_PREFIX}/usr/lib ${MKSYSTEM_TARGET_CFLAGS} " autotoolsBuild "freetype-${FREETYPE_VERSION}" --prefix="/usr" --host="${MKSYSTEM_TARGET}" --build="aarch64-unknown-linux-gnu" --enable-freetype-config --with-brotli=no --with-png=no --with-harfbuzz=no
	popd
	markDone "freetype-stage0"
fi

# Fontconfig
if ! isDone "fontconfig"; then
	pushd "${MKSYSTEM_SOURCES}"
		[ ! -d "fontconfig" ] && git clone --depth=1 "https://gitlab.freedesktop.org/fontconfig/fontconfig"
		pushd "fontconfig"
			/usr/bin/echo -e "#!/bin/python3\nprint('hello world!')" > "conf.d/link_confs.py"
			chmod +x "conf.d/link_confs.py"
		popd
		 mesonBuild "fontconfig" -Dtests=disabled -Ddoc=disabled -Dtools=disabled
	popd
	markDone "fontconfig"
fi
# Harfbuzz
if ! isDone "harfbuzz"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "https://github.com/harfbuzz/harfbuzz/releases/download/${HARFBUZZ_VERSION}/harfbuzz-${HARFBUZZ_VERSION}.tar.xz"
		LDFLAGS="-L${MKSYSTEM_PREFIX}/usr/lib ${MKSYSTEM_TARGET_CFLAGS} " mesonBuild "harfbuzz-${HARFBUZZ_VERSION}" -Dicu=enabled -Dtests=disabled # -Dgraphite=enabled -Dfontconfig=enabled -Dcairo=disabled
	popd
	markDone "harfbuzz"
fi
# Cairo
if ! isDone "cairo"; then
	pushd "${MKSYSTEM_SOURCES}"
		[ ! -d "cairo" ] && git clone --depth=1 "https://github.com/freedesktop/cairo"
		mesonBuild "cairo" -Dgl-backend=glesv3 -Dglesv3=enabled -Ddrm=enabled -Dtee=enabled -Dglib=enabled -Dpng=enabled -Dxcb=disabled -Dxml=disabled -Dzlib=enabled -Dgtk2-utils=disabled -Dopenvg=disabled -Dfontconfig=enabled -Dxlib=disabled -Dtests=disabled
	popd
	markDone "cairo"
fi
# Freetype
if ! isDone "freetype"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "https://downloads.sourceforge.net/freetype/freetype-${FREETYPE_VERSION}.tar.xz"
		LDFLAGS="-L${MKSYSTEM_PREFIX}/usr/lib " autotoolsBuild "freetype-${FREETYPE_VERSION}" --prefix="/usr" --host="${MKSYSTEM_TARGET}" --build="aarch64-unknown-linux-gnu" --enable-freetype-config --with-brotli=no --with-png=yes --with-harfbuzz=yes
	popd
	markDone "freetype"
fi


# fribidi
if ! isDone "fribidi"; then
	pushd "${MKSYSTEM_SOURCES}"
		[ ! -d "fribidi" ] && git clone --depth=1 "https://github.com/fribidi/fribidi"
		mesonBuild "fribidi" -Ddocs=false
	popd
	markDone "fribidi"
fi


# Pango
if ! isDone "pango"; then
	pushd "${MKSYSTEM_SOURCES}"
		[ ! -d "pango" ] && git clone --depth=1 "https://gitlab.gnome.org/GNOME/pango"
		mesonBuild "pango" -Dcairo=enabled -Dfreetype=enabled -Dgtk_doc=false -Dxft=disabled -Dlibthai=disabled
	popd
	markDone "pango"
fi


# SwayWM!
if ! isDone "sway"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "https://github.com/swaywm/sway/releases/download/${SWAY_VERSION}/sway-${SWAY_VERSION}.tar.gz"
		pushd "sway-${SWAY_VERSION}"
			sed -e "s/libsystemd/hiwejdhqwiudqwjduowhqduo/" -e "s/libelogind/ouewjoodiqjdoqijdoiqwjdwq/" -i "meson.build" || true
		popd
		mesonBuild "sway-${SWAY_VERSION}" -Dxwayland=disabled -Dgdk-pixbuf=disabled -Dtray=disabled
	popd
	markDone sway
fi

if ! isDone "swaybg"; then
	pushd "${MKSYSTEM_SOURCES}"
		[ ! -d "swaybg" ] && git clone "https://github.com/swaywm/swaybg"
		mesonBuild "swaybg"
	popd
	markDone "swaybg"
fi


# Unifont
if ! isDone "unifont"; then
	pushd "${MKSYSTEM_SOURCES}"
		download "http://unifoundry.com/pub/unifont/unifont-13.0.03/font-builds/unifont-13.0.03.ttf"
		mkdir -p "${MKSYSTEM_PREFIX}/usr/share/fonts/TTF"
		cp "unifont-13.0.03.ttf" "${MKSYSTEM_PREFIX}/usr/share/fonts/TTF"
	popd
	markDone "unifont"
fi

if ! isDone "libjpeg-turbo"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "https://downloads.sourceforge.net/libjpeg-turbo/libjpeg-turbo-2.0.5.tar.gz"
		cmakeBuild "libjpeg-turbo-2.0.5" -DCMAKE_INSTALL_DEFAULT_LIBDIR=lib
	popd
	markDone libjpeg-turbo
fi

# depends: zlib-ng, libpng, libtiff
if ! isDone "openjpeg"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "https://github.com/uclouvain/openjpeg/archive/v2.3.1/openjpeg-2.3.1.tar.gz"
		cmakeBuild "openjpeg-2.3.1"
	popd
	markDone "openjpeg"
fi

if ! isDone "dbus"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "https://dbus.freedesktop.org/releases/dbus/dbus-1.12.20.tar.gz"
		autotoolsBuild "dbus-1.12.20" \
			--prefix="/usr" \
			--host="${MKSYSTEM_TARGET}" \
			--sysconfdir=/etc \
			--localstatedir=/var \
			--disable-doxygen-docs \
			--disable-xml-docs \
			--with-console-auth-dir=/run/console \
			--disable-systemd \
			--without-x \
			--with-system-pid-file=/run/dbus/pid \
			--with-system-socket=/run/dbus/system_bus_socket
	popd
	markDone dbus
fi

if ! isDone "at-spi2-core"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "http://ftp.gnome.org/pub/gnome/sources/at-spi2-core/2.38/at-spi2-core-2.38.0.tar.xz"
		mesonBuild "at-spi2-core-2.38.0" -Dx11=no
	popd
	markDone "at-spi2-core"
fi

if ! isDone "atk"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "http://ftp.gnome.org/pub/gnome/sources/atk/2.36/atk-2.36.0.tar.xz"
		mesonBuild "atk-2.36.0" -Dintrospection=false
	popd
	markDone "atk"
fi

if ! isDone "at-spi2-atk"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "http://ftp.gnome.org/pub/gnome/sources/at-spi2-atk/2.38/at-spi2-atk-2.38.0.tar.xz"
		mesonBuild "at-spi2-atk-2.38.0" -Dtests=false
	popd
	markDone "at-spi2-atk"
fi

if ! isDone "libepoxy"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "https://github.com/anholt/libepoxy/releases/download/1.5.4/libepoxy-1.5.4.tar.xz"
		mesonBuild "libepoxy-1.5.4" -Dx11=false
		sed "s/Requires.private: gl /Requires.private: /" -i "${MKSYSTEM_PREFIX}/lib/pkgconfig/epoxy.pc"
	popd
	markDone "libepoxy"
fi


if ! isDone "gdk-pixbuf"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "http://ftp.gnome.org/pub/gnome/sources/gdk-pixbuf/2.40/gdk-pixbuf-2.40.0.tar.xz"
		mesonBuild "gdk-pixbuf-2.40.0" -Dx11=false -Dgir=false -Dtiff=false -Dman=false -Ddocs=false 
	popd
	markDone "gdk-pixbuf"
fi


if ! isDone "gtk"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "http://ftp.gnome.org/pub/gnome/sources/gtk+/3.24/gtk+-3.24.23.tar.xz"
		mesonBuild "gtk+-3.24.23" -Dintrospection=false  -Dinstalled_tests=true -Dx11_backend=false -Dbroadway_backend=true -Dprint_backends=file
	popd
	markDone "gtk"
fi

if ! isDone "libxml2"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "http://xmlsoft.org/sources/libxml2-2.9.10.tar.gz"
		autotoolsBuild "libxml2-2.9.10" \
			--prefix="/usr" \
			--host="${MKSYSTEM_TARGET}" \
			--with-sysroot="${MKSYSTEM_PREFIX}" \
			--without-history \
			--without-lzma
	popd
	markDone "libxml2"
fi

# depends: libxml2
if ! isDone "libxslt"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "http://xmlsoft.org/sources/libxslt-1.1.34.tar.gz"
		autotoolsBuild "libxslt-1.1.34" \
			--prefix="/usr" \
			--host="${MKSYSTEM_TARGET}" \
			--with-sysroot="${MKSYSTEM_PREFIX}" \
			--without-python
	popd
	markDone "libxslt"
fi

if ! isDone "shared-mime-info"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "https://gitlab.freedesktop.org/xdg/shared-mime-info/uploads/0440063a2e6823a4b1a6fb2f2af8350f/shared-mime-info-2.0.tar.xz"
		mesonBuild "shared-mime-info-2.0" -Dupdate-mimedb=true
	popd
	markDone "shared-mime-info"
fi

if ! isDone "bash"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "https://ftp.gnu.org/gnu/bash/bash-5.0.tar.gz"
		autotoolsBuild "bash-5.0" \
			--prefix="/usr" \
			--host="${MKSYSTEM_TARGET}" --without-bash-malloc 
	popd
	markDone "bash"
fi

if ! isDone "distro-files"; then
	cp "${MKSYSTEM_FILES}/os-release" "${MKSYSTEM_PREFIX}/etc/os-release"
	cp "${MKSYSTEM_FILES}/lsb-release" "${MKSYSTEM_PREFIX}/etc/lsb-release"
	markDone "distro-files"
fi 


if ! isDone "neofetch"; then
	pushd "${MKSYSTEM_SOURCES}"
		download "https://github.com/dylanaraps/neofetch/raw/master/neofetch"
		cp "neofetch" "${MKSYSTEM_PREFIX}/usr/bin/neofetch"
		chmod +x "${MKSYSTEM_PREFIX}/usr/bin/neofetch"
		mkdir -p "${MKSYSTEM_PREFIX}/etc/neofetch"
		cp "${MKSYSTEM_FILES}/neofetch_config" "${MKSYSTEM_PREFIX}/etc/neofetch/config"
	popd
	markDone "neofetch"
fi


if ! isDone "vte"; then
	pushd "${MKSYSTEM_SOURCES}"
		[ ! -d "vte" ] && git clone --depth=1 "https://gitlab.gnome.org/GNOME/vte.git"
		pushd "vte"
			git apply "${MKSYSTEM_FILES}/vte.patch" || true
		popd
		mesonBuild "vte" -Dsixel=true -Dgnutls=true -Dglade=false -Dicu=true -D_systemd=false -Dvapi=false -Ddocs=false -Dgir=false
	popd
	markDone "vte"
fi

if ! isDone "chaos"; then
	pushd "${MKSYSTEM_SOURCES}"
		[ ! -d "chaos" ] && git clone --depth=1 "https://github.com/purringChaos/chaos"
		mesonBuild "chaos"
	popd
	markDone "chaos"
fi

if ! isDone "nasm-symlink"; then
	ln -sf "/usr/bin/nasm" "${MKSYSTEM_CROSS_TOOLS}/bin/${MKSYSTEM_TARGET}-nasm"
	markDone "nasm-symlink"
fi


if ! isDone "alsa-lib"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "ftp://ftp.alsa-project.org/pub/lib/alsa-lib-${ALSA_LIB_VERSION}.tar.bz2"
		autotoolsBuild "alsa-lib-${ALSA_LIB_VERSION}" \
			--prefix="/usr" \
			--host="${MKSYSTEM_TARGET}"
		sed 's/ssize_t/size_t/g' "${MKSYSTEM_PREFIX}/usr/include/alsa/input.h" -i
		sed 's/ssize_t/size_t/g' "${MKSYSTEM_PREFIX}/usr/include/alsa/pcm.h" -i
	popd
	markDone "alsa-lib"
fi

if ! isDone "libogg"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "https://downloads.xiph.org/releases/ogg/libogg-${LIBOGG_VERSION}.tar.xz"
		autotoolsBuild "libogg-${LIBOGG_VERSION}" \
			--prefix="/usr" \
			--host="${MKSYSTEM_TARGET}"
	popd
	markDone "libogg"
fi

if ! isDone "libvorbis"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "https://downloads.xiph.org/releases/vorbis/libvorbis-${LIBVORBIS_VERSION}.tar.xz"
		PKG_CONFIG="${MKSYSTEM_MISC}/pkgconf" autotoolsBuild "libvorbis-${LIBVORBIS_VERSION}" \
			--prefix="/usr" \
			--host="${MKSYSTEM_TARGET}"
	popd
	markDone "libvorbis"
fi

if ! isDone "flac"; then
	pushd "${MKSYSTEM_SOURCES}"
		[ ! -d "flac" ]  && git clone --depth=1 "https://github.com/xiph/flac"
		pushd "flac"
			sed "s#I\$prefix/include#I\$ogg_prefix/include#" "m4/ogg.m4" -i
		popd
		PKG_CONFIG="${MKSYSTEM_MISC}/pkgconf" autotoolsBuild "flac" \
			--prefix="/usr" \
			--host="${MKSYSTEM_TARGET}"

	popd
	markDone "flac"
fi

if ! isDone "libsndfile"; then
	pushd "${MKSYSTEM_SOURCES}"
		[ ! -d "libsndfile" ] && git clone "https://github.com/libsndfile/libsndfile"
		CFLAGS="${MKSYSTEM_TARGET_CFLAGS}" PKG_CONFIG="${MKSYSTEM_MISC}/pkgconf" autotoolsBuild "libsndfile" \
			--prefix="/usr" \
			--host="${MKSYSTEM_TARGET}" --disable-alsa --disable-full-suite
	popd
	markDone "libsndfile"
fi

if ! isDone "soxr"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "https://downloads.sourceforge.net/project/soxr/soxr-0.1.3-Source.tar.xz"
		cmakeBuild "soxr-0.1.3-Source" \
			-DBUILD_EXAMPLES='OFF' \
			-DBUILD_SHARED_LIBS='ON' \
			-DWITH_AVFFT='ON' \
			-DWITH_LSR_BINDINGS='ON' \
			-DWITH_OPENMP='ON' \
			-DWITH_PFFFT='ON'
	popd
	markDone "soxr"
fi

if ! isDone "fftw"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "http://www.fftw.org/fftw-3.3.8.tar.gz"
		FFTW_CONFIGURE_ARGS="--prefix=/usr --host=${MKSYSTEM_TARGET} --enable-neon --enable-generic-simd128  --enable-generic-simd256 --enable-threads --disable-static --enable-shared"
		autotoolsBuild "fftw-3.3.8" ${FFTW_CONFIGURE_ARGS[@]}
		autotoolsBuild "fftw-3.3.8" ${FFTW_CONFIGURE_ARGS[@]} --enable-float
	popd
	markDone "fftw"
fi

if ! isDone "libtool"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "http://ftp.gnu.org/gnu/libtool/libtool-2.4.6.tar.xz"
		autotoolsBuild "libtool-2.4.6" --prefix=/usr --host=${MKSYSTEM_TARGET}
	popd
	markDone "libtool"
fi

# ew but required 😔👊
if ! isDone "pulseaudio"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "https://www.freedesktop.org/software/pulseaudio/releases/pulseaudio-13.0.tar.xz"
		mesonBuild "pulseaudio-13.0" -Dman=false -Dtests=false -Ddatabase=simple -Dalsa=enabled -Dbluez5=false -Ddbus=disabled -Dfftw=enabled -Dglib=disabled -Dgsettings=disabled -Dgtk=disabled -Dipv6=true -Dopenssl=disabled -Dudev=enabled -Dx11=disabled -Dsoxr=enabled -Dsystemd=disabled -Dlirc=disabled -Dasyncns=disabled -Davahi=disabled -Dorc=disabled -Dadrian-aec=true -Dwebrtc-aec=disabled -Dspeex=disabled -Djack=disabled
	popd
	markDone "pulseaudio"
fi

# ew but required 😔👊
if ! isDone "dotuwu"; then
	pushd "${MKSYSTEM_PREFIX}"
		mkdir -p "home/kitteh"
		pushd "home/kitteh"
			[ -d ".uwu" ] && rm -rf ".uwu"
			git clone "https://github.com/purringChaos/dotuwu" ".uwu"
			pushd ".uwu"
				INSTALL_DIR="${MKSYSTEM_PREFIX}/home/kitteh" bash ./install
			popd
		popd
	popd
	markDone "dotuwu"
fi

# depends: created prefix
if ! isDone "timezones"; then
	cat "/etc/localtime" > "${MKSYSTEM_PREFIX}/etc/localtime"
	markDone "timezones"
fi

# depends: nothing
if ! isDone "zar"; then
	pushd "${MKSYSTEM_SOURCES}"
		[ ! -d "zar" ] && git clone --depth=1 --recursive "https://github.com/purringChaos/zar"
		pushd "zar"
			git submodule update --init
			zig build -Dweather_location="${WEATHER_LOCATION:-London}"
			cp "zig-cache/bin/zar" "${MKSYSTEM_PREFIX}/usr/bin/zar"
		popd
	popd
	markDone "zar"
fi

# depends: literally everything
if ! isDone "ffmpeg"; then
	pushd "${MKSYSTEM_SOURCES}"
		[ ! -d "ffmpeg" ] && git clone --depth=1 "https://git.ffmpeg.org/ffmpeg.git" "ffmpeg"
		PKG_CONFIG=${MKSYSTEM_MISC}/pkgconf \
		PKG_CONFIG_LIBDIR="${MKSYSTEM_PREFIX}/usr/lib" \
		PKG_CONFIG_PATH="${MKSYSTEM_PREFIX}/usr/lib/pkgconfig" \
		autotoolsBuild "ffmpeg" \
			--target-os=linux \
			--arch=aarch64 \
			--enable-cross-compile \
			--cross-prefix=${MKSYSTEM_TARGET}- \
			--prefix=/usr \
			--pkg-config=${MKSYSTEM_MISC}/pkgconf \
			--disable-static  \
			--enable-shared \
			--disable-htmlpages \
			--disable-manpages \
			--disable-doc \
			--disable-debug \
			--enable-gpl \
			--enable-version3 \
			--enable-ffmpeg \
			--enable-ffprobe
	popd
	markDone "ffmpeg"
fi


# depends: freetype, fribidi, fontconfig, harfbuzz
if ! isDone "libass"; then
	pushd "${MKSYSTEM_SOURCES}"
		[ ! -d "libass" ] &&  git clone --depth=1 "https://github.com/libass/libass"
		autotoolsBuild "libass" --prefix=/usr --host=${MKSYSTEM_TARGET}
	popd
	markDone "libass"
fi

if ! isDone "luajit"; then
	pushd "${MKSYSTEM_SOURCES}"
		[ ! -d "LuaJIT" ] &&  git clone --depth=1 "https://github.com/LuaJIT/LuaJIT"
		pushd "LuaJIT"
			CROSS="${MKSYSTEM_TARGET}-" \
			HOST_CC="${MKSYSTEM_TARGET}-gcc" \
			TARGET_CFLAGS="${MKSYSTEM_TARGET_CFLAGS}" \
				make "${MAKEFLAGS}"
			make install \
				PREFIX=/usr \
				DESTDIR="${MKSYSTEM_PREFIX}" \
				"${MAKEFLAGS}"
		popd
		ln -sf luajit-2.1.0-beta3 "${MKSYSTEM_PREFIX}/usr/bin/luajit"
	popd
	markDone "luajit"
fi

if ! isDone "mpv"; then
	pushd "${MKSYSTEM_SOURCES}"
		[ ! -d "mpv" ] && git clone --depth=1 "https://github.com/mpv-player/mpv"
		pushd "mpv"
			./bootstrap.py
			CC=${MKSYSTEM_TARGET}-gcc \
			CFLAGS="${MKSYSTEM_TARGET_CFLAGS} -I${MKSYSTEM_PREFIX}/usr/include" \
			LDFLAGS="${MKSYSTEM_TARGET_CFLAGS} -L${MKSYSTEM_PREFIX}/usr/lib" \
			PKG_CONFIG=${MKSYSTEM_MISC}/pkgconf \
			PKG_CONFIG_LIBDIR="${MKSYSTEM_PREFIX}/usr/lib" \
			PKG_CONFIG_PATH="${MKSYSTEM_PREFIX}/usr/lib/pkgconfig:${MKSYSTEM_PREFIX}/usr/share/pkgconfig" \
			./waf configure -p \
				--prefix=/usr \
				--target=${MKSYSTEM_TARGET} \
				--disable-vaapi \
				--disable-vulkan \
				--disable-lua \
				--disable-rubberband \
				--disable-x11 \
				--disable-javascript \
				--disable-libplacebo \
				--disable-lua \
				--disable-cuda-hwaccel \
				--disable-cuda-interop \
				--disable-libbluray \
				--disable-caca 
			./waf build "${MAKEFLAGS}" -v
			./waf install --destdir=${MKSYSTEM_PREFIX} "${MAKEFLAGS}"
		popd
	popd
	markDone "mpv"
fi

if ! isDone "webkit2gtk"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "https://webkitgtk.org/releases/webkitgtk-2.30.1.tar.xz"
		PKG_CONFIG=${MKSYSTEM_MISC}/pkgconf \
		PKG_CONFIG_LIBDIR="${MKSYSTEM_PREFIX}/usr/lib" \
		PKG_CONFIG_PATH="${MKSYSTEM_PREFIX}/usr/lib/pkgconfig:${MKSYSTEM_PREFIX}/usr/share/pkgconfig" \
		cmakeBuild "webkitgtk-2.30.1" \
			-DCMAKE_INSTALL_PREFIX=/usr \
			-DCMAKE_SKIP_RPATH=ON \
			-DPORT=GTK \
			-DLIB_INSTALL_DIR=/usr/lib \
			-DUSE_LIBHYPHEN=OFF \
			-DENABLE_SPELLCHECK=OFF \
			-DENABLE_MINIBROWSER=ON \
			-DUSE_WOFF2=OFF \
			-DUSE_WPE_RENDERER=OFF \
			-DUSE_SYSTEMD=OFF \
			-DENABLE_X11_TARGET=OFF \
			-DENABLE_GLES2=ON \
			-DDUSE_WPE_RENDERER=ON \
			-DCMAKE_DISABLE_FIND_PACKAGE_OpenGL=ON \
			-DUSE_LIBSECRET=OFF \
			-DENABLE_INTROSPECTION=OFF \
			-DUSE_WOFF2=OFF \
			-DENABLE_WAYLAND_TARGET=ON \
			-DENABLE_BUBBLEWRAP_SANDBOX=OFF \
			-DENABLE_VIDEO=OFF \
			-DENABLE_WEB_AUDIO=OFF \
			-DUSE_LIBNOTIFY=OFF
			-Wno-dev
	exit
	popd
	markDone "webkit2gtk"
fi


# EEND
exit

exit

# TODO
if [ "${NO_MKIMAGE}z" == "z" ]; then
	mkdir -p "${MKSYSTEM_ROOT}/out"
	pushd "${MKSYSTEM_ROOT}/out"
		sudo losetup -D
		sudo rm out.img
		sudo umount mountpoint || true
		sudo rm -rf mountpoint || true
		fallocate -l 8GB out.img
		
		parted out.img mklabel msdos
		parted out.img mkpart primary ext4 1% 100%
		sudo losetup -fP out.img
		LOOP_DEVICE=$(losetup -j out.img | sed "s/:.*//")
		sudo mkfs.ext2 "${LOOP_DEVICE}p1"
		mkdir "mountpoint"
		sudo mount "${LOOP_DEVICE}p1" mountpoint
		sudo rsync -aAXv "${MKSYSTEM_PREFIX}/" --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found"} "mountpoint"
		
		
	popd


fi




