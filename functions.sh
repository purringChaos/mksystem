function download() {
	if [ ! -f "$(basename "${2:-$(basename "$1")}")" ]; then
		aria2c -x4 -s4 "${1}"
	fi
}

function extract() {
	DIR="${2:-$(basename "${1}" | sed s/.tar.*$// | sed s/.t[gx]z$//)}"
	if [ ! -d "${DIR}" ]; then
		bsdtar xf "$(basename "${1}")"
	fi
}

function downloadExtract() {
	download "${1}" "${2}"
	extract "${2:-${1}}" "${3}"
}

function markDone() {
	touch "${MKSYSTEM_STATE}/${1}"
}

function isDone() {
	[ -f "${MKSYSTEM_STATE}/${1}" ]
}

function mesonBuild() {
	PKG="${1}"
	shift
	mkdir -p "${PKG}-build"
	pushd "${PKG}-build"
		PKG_CONFIG="${MKSYSTEM_MISC}/pkgconf" PKG_CONFIG_PATH="${MKSYSTEM_PREFIX}/usr/lib/pkgconfig" meson . "../${PKG}" --cross-file="${MKSYSTEM_MISC}/meson.cross" -Dprefix="/usr" "$@"
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
		PKG_CONFIG_PATH="${MKSYSTEM_PREFIX}/usr/lib/pkgconfig" ./configure "$@"
		unset CFLAGS
		unset CXXFLAGS
		CFLAGS="${CFLAGS_BAK}"
		make "${MAKEFLAGS}" V=1
		if [ "${DEST}z" != "z" ]; then 
			DESTDIR="${DEST}" make install "${MAKEFLAGS}"
		else
			DESTDIR="${MKSYSTEM_PREFIX}" make install DESTDIR="${MKSYSTEM_PREFIX}" "${MAKEFLAGS}" V=1
		fi
		make clean "${MAKEFLAGS}"
	popd
}


function cmakeConfigure() {
	cmake -GNinja . \
		-DCMAKE_SYSTEM_PROCESSOR="aarch64" \
		-DCMAKE_BUILD_TYPE='Release' \
		-DCMAKE_C_COMPILER="${MKSYSTEM_TARGET}-gcc" \
		-DCMAKE_CXX_COMPILER="${MKSYSTEM_TARGET}-g++" \
		-DCMAKE_FIND_ROOT_PATH="${MKSYSTEM_PREFIX}" \
		-DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
		-DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
		-DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
		-DCMAKE_SYSTEM_NAME=Linux -DCMAKE_SYSROOT="${MKSYSTEM_PREFIX}" \
		-DCMAKE_C_FLAGS="${MKSYSTEM_TARGET_CFLAGS}" \
		-DCMAKE_CXX_FLAGS="${MKSYSTEM_TARGET_CFLAGS}" \
		-DCMAKE_INSTALL_PREFIX="/usr" \
		-DCMAKE_BUILD_SHARED_LIBS=on \
		"$@"
}

function cmakeBuild() {
	pushd "${1}"
		shift
		cmakeConfigure "$@"
		ninja "${MAKEFLAGS}" -v
		DESTDIR="${MKSYSTEM_PREFIX}" ninja install "${MAKEFLAGS}"
		ninja clean "${MAKEFLAGS}"
	popd
}
