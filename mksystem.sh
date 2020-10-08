#!/bin/bash
set -e
set -x
set -o pipefail
shopt -s extglob

ROOT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

export PATH="/usr/lib/ccache/bin:${PATH}"

# Env
# CPU stuff
MKSYSTEM_ARCH=armv8-a+crypto+crc
MKSYSTEM_HOST=$(echo ${MACHTYPE} | sed "s/-[^-]*/-cross/")
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

export PATH="${MKSYSTEM_CCACHE_BIN}:${MKSYSTEM_CROSS_TOOLS}/bin:${MKSYSTEM_CROSS_TOOLS_TARGET}/bin:${PATH}"


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
GRAPHITE2_VERSION=1.3.14
FREETYPE_VERSION=2.10.2
HARFBUZZ_VERSION=2.7.2
SWAY_VERSION=1.5
XKEYBOARD_CONFIG_VERSION=2.30
UTIL_LINUX_VERSION=2.36
# VVER

# Misc Functions
function download() {
	if [ ! -f "$(basename "${1}")" ]; then
		aria2c -x4 -s4 "${1}"
	fi
}

function extract() {
	DIR="${2:-$(echo "$(basename "${1}")" | sed s/.tar.*$// | sed s/.t[gx]z$//)}"
	if [ ! -d "${DIR}" ]; then
		bsdtar xf "$(basename "${1}")"
	fi
}

function downloadExtract() {
	download "${1}"
	extract "${1}"
}

function markDone() {
	touch "${MKSYSTEM_STATE}/installed/${1}"
}

function isDone() {
	[ -f "${MKSYSTEM_STATE}/installed/${1}" ]
}

function mesonBuild() {
	PKG="${1}"
	shift
	mkdir -p "${PKG}-build"
	pushd "${PKG}-build"
		PKG_CONFIG="${MKSYSTEM_MISC}/pkgconf" PKG_CONFIG_PATH="${MKSYSTEM_PREFIX}/usr/lib/pkgconfig" meson . "../${PKG}" --cross-file="${MKSYSTEM_MISC}/meson.cross" -Dprefix="/usr" $@
		ninja "${MAKEFLAGS}"
		DESTDIR="${MKSYSTEM_PREFIX}" ninja install "${MAKEFLAGS}"
		ninja clean "${MAKEFLAGS}"
	popd
	rm -rf "${PKG}-build"
}

function autotoolsBuild() {
	NAME="${1}"
	pushd "${NAME}"
		shift
		[ ! -f "configure" ] && [ -f "buildconf.sh" ] && ./buildconf.sh
		[ ! -f "configure" ] && [ -f "autogen.sh" ] && ./autogen.sh
		[ ! -f "configure" ] && autoreconf -fi
		CFLAGS_BAK="${CFLAGS}"
		[ "${DEST}z" == "z" ] && export CFLAGS="${MKSYSTEM_TARGET_CFLAGS}" CXXFLAGS="${MKSYSTEM_TARGET_CFLAGS}"
		PKG_CONFIG_PATH="${MKSYSTEM_PREFIX}/usr/lib/pkgconfig" ./configure $@
		unset CFLAGS
		unset CXXFLAGS
		CFLAGS="${CFLAGS_BAK}"
		make "${MAKEFLAGS}"
		if [ "${DEST}z" != "z" ]; then 
			DESTDIR="${DEST}" make install "${MAKEFLAGS}"
		else
			DESTDIR="${MKSYSTEM_PREFIX}" make install "${MAKEFLAGS}" V=1
		fi
		make clean "${MAKEFLAGS}"
	popd
}

function cmakeBuild() {
	pushd "${1}"
		shift
		cmake -GNinja . -DCMAKE_SYSTEM_PROCESSOR="aarch64" -DCMAKE_C_COMPILER="${MKSYSTEM_TARGET}-gcc" -DCMAKE_CXX_COMPILER="${MKSYSTEM_TARGET}-g++" -DCMAKE_FIND_ROOT_PATH="${MKSYSTEM_PREFIX}" -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY -DCMAKE_SYSTEM_NAME=Linux -DCMAKE_SYSROOT="${MKSYSTEM_PREFIX}" -DCMAKE_C_FLAGS="${MKSYSTEM_TARGET_CFLAGS}" -DCMAKE_CXX_FLAGS="${MKSYSTEM_TARGET_CFLAGS}" -DCMAKE_INSTALL_PREFIX="/usr" $@
		ninja "${MAKEFLAGS}"
		DESTDIR="${MKSYSTEM_PREFIX}" ninja install "${MAKEFLAGS}"
		ninja clean "${MAKEFLAGS}"
	popd
}

# Make all needed folders.

mkdir -p "${MKSYSTEM_ROOT}"
mkdir -p "${MKSYSTEM_STATE}" "${MKSYSTEM_STATE}/installed"
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
		cp -v "${MKSYSTEM_CROSS_TOOLS_TARGET}/lib64/"* "lib/"
	popd
	markDone "copy-gcc-libs"
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
cpu = 'armv8-a'
endian = 'little'
EOF
	popd
	markDone "meson-cross-make"
fi


# Install proper final musl.
if ! isDone "final-musl"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "http://musl.libc.org/releases/musl-${MUSL_VERSION}.tar.gz"
		DEST="${MKSYSTEM_PREFIX}" autotoolsBuild "musl-${MUSL_VERSION}" CROSS_COMPILE="${MKSYSTEM_TARGET}-" --prefix="/usr" --target="${MKSYSTEM_TARGET}"
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
		CC="${MKSYSTEM_TARGET}-gcc" autotoolsBuild "zlib-ng" --prefix="/usr" --zlib-compat
	popd
	markDone "zlib-ng"
fi

# install lzo
if ! isDone "lzo"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "http://www.oberhumer.com/opensource/lzo/download/lzo-2.10.tar.gz"
		autotoolsBuild "lzo-2.10" --prefix="/usr" --host="${MKSYSTEM_TARGET}"
	popd
fi

# Install libffi for cross-language calls.
if ! isDone "libffi"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "https://github.com/libffi/libffi/releases/download/v${LIBFFI_VERSION}/libffi-${LIBFFI_VERSION}.tar.gz"
		autotoolsBuild "libffi-${LIBFFI_VERSION}" --prefix="/usr" --host="${MKSYSTEM_TARGET}"
	popd
	markDone "libffi"
fi

# Install libpng.
if ! isDone "libpng"; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract "https://downloads.sourceforge.net/libpng/libpng-${LIBPNG_VERSION}.tar.xz"
		CC="${MKSYSTEM_TARGET}-gcc ${MKSYSTEM_TARGET_CFLAGS}" autotoolsBuild "libpng-${LIBPNG_VERSION}" --prefix="/usr" --host="${MKSYSTEM_TARGET}"
	popd
	markDone "libpng"
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
		LDFLAGS="-L${MKSYSTEM_PREFIX}/usr/lib ${CFLAGS} " autotoolsBuild "freetype-${FREETYPE_VERSION}" --prefix="/usr" --host="${MKSYSTEM_TARGET}" --build="aarch64-unknown-linux-gnu" --enable-freetype-config --with-brotli=no --with-png=no --with-harfbuzz=no
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
		LDFLAGS="-L${MKSYSTEM_PREFIX}/usr/lib ${CFLAGS} " mesonBuild "harfbuzz-${HARFBUZZ_VERSION}" -Dicu=disabled -Dtests=disabled # -Dgraphite=enabled -Dfontconfig=enabled -Dcairo=disabled
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

# EEND

exit


if ! isDone ""; then
	pushd "${MKSYSTEM_SOURCES}"
		downloadExtract ""
		mesonBuild ""
	popd
	markDone ""
fi
