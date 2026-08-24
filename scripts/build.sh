#!/usr/bin/env bash
# Build yosys from source with static-runtime linkage for portability
# Target: RHEL 8+ / glibc >= 2.28, x86-64-v3
set -euo pipefail

TAG="${1:?Usage: $0 <yosys-git-tag>}"
VERSION="${TAG#v}"
# Package iteration: bump when repackaging the same upstream version
ITERATION=2

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/../build"
BUILD_PY_DIR="${SCRIPT_DIR}/../build-pyosys"
STAGING_DIR="${SCRIPT_DIR}/../staging"
STAGING_PY_DIR="${SCRIPT_DIR}/../staging-pyosys"
STAGING_DEB_PY_DIR="${SCRIPT_DIR}/../staging-deb-pyosys"
DIST_DIR="${SCRIPT_DIR}/../dist"
SRC_DIR="${SCRIPT_DIR}/../yosys-src"

# ----- Enable GCC 14 from gcc-toolset-14 -----
source /opt/rh/gcc-toolset-14/enable

# ----- Clone yosys -----
if [ ! -d "${SRC_DIR}" ]; then
	git clone --branch "${TAG}" \
		--depth 1 --recurse-submodules --shallow-submodules \
		https://github.com/YosysHQ/yosys.git "${SRC_DIR}"
fi

# ----- Common flags -----
# pkg-config does not search /usr/local/lib/pkgconfig by default; without this,
# yosys links the distro readline (so.7) / libffi (so.6) instead of our static
# /usr/local builds, breaking DEB on distros whose libffi soname differs (so.7+).
export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"

CFLAGS="-march=x86-64-v3 -mtune=generic -O3 -w -fno-math-errno -fno-trapping-math"
CXXFLAGS="${CFLAGS}"
LDFLAGS="-static-libgcc -static-libstdc++ -Wl,--as-needed -Wl,-z,relro -Wl,-z,now"
COMMON_CMAKE_ARGS=(
	-G Ninja
	-DCMAKE_BUILD_TYPE=Release
	-DCMAKE_C_COMPILER=gcc
	-DCMAKE_CXX_COMPILER=g++
	-DCMAKE_INSTALL_PREFIX=/usr
	-DCMAKE_C_FLAGS="${CFLAGS}"
	-DCMAKE_CXX_FLAGS="${CXXFLAGS}"
	-DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS}"
)
# Note: same configure options as yosys' official CI (no LTO, no
# YOSYS_USE_BUNDLED_LIBS - that option is unused in v0.68 anyway, no
# BUILD_SHARED_LIBS - the default is OFF). The static readline/libffi and the
# new toolchain are supplied via PKG_CONFIG_PATH / PATH, not via CMake flags.

# ----- Build 1: main binary, WITHOUT python -----
# With YOSYS_WITH_PYTHON=ON the yosys driver links libpython directly, which would
# force a python3.9 runtime dependency on the main package (and break the DEB on
# Ubuntu 20.04+/Debian 10). Python support ships as a separate subpackage instead.
rm -rf "${BUILD_DIR}"
cmake -B "${BUILD_DIR}" -S "${SRC_DIR}" \
	"${COMMON_CMAKE_ARGS[@]}" \
	-DYOSYS_WITH_PYTHON=OFF

# Build quietly: third-party code (ABC...) emits lots of GCC warnings/notes.
# Log to a file; only show the tail on failure.
if ! cmake --build "${BUILD_DIR}" -j"$(nproc)" >/tmp/yosys-build.log 2>&1; then
	echo "FAIL: yosys build failed, last lines of the log:"
	tail -n 120 /tmp/yosys-build.log
	exit 1
fi

# ----- Functional check (same as yosys' official test-compile CI step) -----
"${BUILD_DIR}/yosys" -p "read_verilog -sv ${SRC_DIR}/tests/simple/always01.v; synth -run coarse;"

# ----- Build 2: pyosys Python module (python-only build, same pattern as upstream wheels) -----
# YOSYS_INSTALL_PYTHON_SITEDIR is set to the RHEL-style purelib path
# (/usr/lib/python3.9/site-packages, where EL8's python39 looks). Debian
# python3 does NOT search that path (it uses /usr/lib/python3/dist-packages),
# so the DEB is repacked from a Debian-layout staging below.
rm -rf "${BUILD_PY_DIR}"
cmake -B "${BUILD_PY_DIR}" -S "${SRC_DIR}" \
	"${COMMON_CMAKE_ARGS[@]}" \
	-DYOSYS_WITH_PYTHON=ON \
	-DYOSYS_INSTALL_PYTHON=ON \
	-DYOSYS_INSTALL_DRIVER=OFF \
	-DYOSYS_INSTALL_LIBRARY=OFF \
	-DYOSYS_BUILD_PYTHON_ONLY=ON \
	-DYOSYS_INSTALL_PYTHON_SITEDIR=/usr/lib/python3.9/site-packages

if ! cmake --build "${BUILD_PY_DIR}" -j"$(nproc)" >/tmp/yosys-build-py.log 2>&1; then
	echo "FAIL: pyosys build failed, last lines of the log:"
	tail -n 120 /tmp/yosys-build-py.log
	exit 1
fi

# ----- Install to staging -----
rm -rf "${STAGING_DIR}" "${STAGING_PY_DIR}"
DESTDIR="${STAGING_DIR}" cmake --install "${BUILD_DIR}" --strip
DESTDIR="${STAGING_PY_DIR}" cmake --install "${BUILD_PY_DIR}" --strip

# ----- Build RPM / DEB packages -----
mkdir -p "${DIST_DIR}"

# RPM: main package (glibc >= 2.28, tcl, zlib, ncurses termcap)
fpm -s dir -t rpm \
	-n yosys \
	-v "${VERSION}" \
	--iteration "${ITERATION}" \
	--architecture x86_64 \
	--description "Yosys Open SYnthesis Suite - RTL synthesis framework" \
	--url "https://yosyshq.net/yosys/" \
	--license ISC \
	--maintainer yosys-build \
	--rpm-os linux \
	--no-auto-depends \
	--depends "glibc >= 2.28" \
	--depends tcl \
	--depends zlib \
	--depends ncurses-libs \
	-p "${DIST_DIR}/yosys-${VERSION}-${ITERATION}.el8.x86_64.rpm" \
	-C "${STAGING_DIR}" usr/

# DEB: main package (libc6 >= 2.28, tcl8.6, zlib1g, ncursesw + tinfo)
fpm -s dir -t deb \
	-n yosys \
	-v "${VERSION}" \
	--iteration "${ITERATION}" \
	--architecture amd64 \
	--description "Yosys Open SYnthesis Suite - RTL synthesis framework" \
	--url "https://yosyshq.net/yosys/" \
	--license ISC \
	--maintainer yosys-build \
	--no-auto-depends \
	--depends "libc6 (>= 2.28)" \
	--depends tcl8.6 \
	--depends zlib1g \
	--depends libncursesw6 \
	--depends libtinfo6 \
	-p "${DIST_DIR}/yosys-${VERSION}-${ITERATION}_amd64.deb" \
	-C "${STAGING_DIR}" usr/

# RPM: pyosys Python 3.9 bindings (self-contained: module + abc + techlibs)
fpm -s dir -t rpm \
	-n yosys-python \
	-v "${VERSION}" \
	--iteration "${ITERATION}" \
	--architecture x86_64 \
	--description "Pyosys - Yosys Python 3.9 bindings (import pyosys)" \
	--url "https://yosyshq.net/yosys/" \
	--license ISC \
	--maintainer yosys-build \
	--rpm-os linux \
	--no-auto-depends \
	--depends "glibc >= 2.28" \
	--depends python39-libs \
	--depends tcl \
	--depends zlib \
	--depends ncurses-libs \
	-p "${DIST_DIR}/yosys-python-${VERSION}-${ITERATION}.el8.x86_64.rpm" \
	-C "${STAGING_PY_DIR}" usr/

# DEB: python3-yosys (Debian 11 / python3.9). Debian's python3 only searches
# /usr/lib/python3/dist-packages, not the RHEL-style site-packages path, so
# repack the module into a Debian-layout staging tree.
rm -rf "${STAGING_DEB_PY_DIR}"
mkdir -p "${STAGING_DEB_PY_DIR}/usr/lib/python3/dist-packages"
cp -a "${STAGING_PY_DIR}/usr/lib/python3.9/site-packages/pyosys" \
	"${STAGING_DEB_PY_DIR}/usr/lib/python3/dist-packages/"

fpm -s dir -t deb \
	-n python3-yosys \
	-v "${VERSION}" \
	--iteration "${ITERATION}" \
	--architecture amd64 \
	--description "Pyosys - Yosys Python 3.9 bindings (import pyosys)" \
	--url "https://yosyshq.net/yosys/" \
	--license ISC \
	--maintainer yosys-build \
	--no-auto-depends \
	--depends "libc6 (>= 2.28)" \
	--depends libpython3.9 \
	--depends tcl8.6 \
	--depends zlib1g \
	--depends libncursesw6 \
	--depends libtinfo6 \
	-p "${DIST_DIR}/python3-yosys-${VERSION}-${ITERATION}_amd64.deb" \
	-C "${STAGING_DEB_PY_DIR}" usr/

# ----- Print summary -----
echo ""
echo "===== Build complete: yosys ${VERSION} (iteration ${ITERATION}) ====="
ls -lh "${DIST_DIR}/"
echo ""
echo "Binary requires:"
echo "  glibc >= 2.28 (RHEL 8+, Ubuntu 20.04+, Debian 10+)"
echo "  CPU: x86-64-v3 (Haswell 2013+)"
echo ""
echo "Main binary dynamic library dependencies:"
ldd "${STAGING_DIR}/usr/bin/yosys" 2>/dev/null || true
echo ""
echo "pyosys module dynamic library dependencies:"
ldd "${STAGING_PY_DIR}/usr/lib/python3.9/site-packages/pyosys/libyosys.so" 2>/dev/null || true
