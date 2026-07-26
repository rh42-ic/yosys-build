#!/usr/bin/env bash
# Build yosys from source with static-runtime linkage for portability
# Target: RHEL 8+ / glibc ≥ 2.28, x86-64-v3
set -euo pipefail

TAG="${1:?Usage: $0 <yosys-git-tag>}"
VERSION="${TAG#v}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/../build"
STAGING_DIR="${SCRIPT_DIR}/../staging"
DIST_DIR="${SCRIPT_DIR}/../dist"
SRC_DIR="${SCRIPT_DIR}/../yosys-src"

# ----- Enable GCC 12 from gcc-toolset-12 -----
source /opt/rh/gcc-toolset-12/enable

# ----- Clone yosys -----
if [ ! -d "${SRC_DIR}" ]; then
	git clone --branch "${TAG}" \
		--depth 1 --recurse-submodules --shallow-submodules \
		https://github.com/YosysHQ/yosys.git "${SRC_DIR}"
fi

# ----- Configure -----
CFLAGS="-march=x86-64-v3 -mtune=generic -O3 -fno-math-errno -fno-trapping-math"
CXXFLAGS="${CFLAGS}"
LDFLAGS="-static-libgcc -static-libstdc++ -Wl,--as-needed -Wl,-z,relro -Wl,-z,now"

cmake -B "${BUILD_DIR}" -G Ninja \
	-S "${SRC_DIR}" \
	-DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_C_COMPILER=gcc \
	-DCMAKE_CXX_COMPILER=g++ \
	-DCMAKE_INSTALL_PREFIX=/usr \
	-DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON \
	-DCMAKE_C_FLAGS="${CFLAGS}" \
	-DCMAKE_CXX_FLAGS="${CXXFLAGS}" \
	-DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS}" \
	-DYOSYS_USE_BUNDLED_LIBS=ON \
	-DBUILD_SHARED_LIBS=OFF

# ----- Build -----
cmake --build "${BUILD_DIR}" -j$(nproc)

# ----- Install to staging -----
rm -rf "${STAGING_DIR}"
DESTDIR="${STAGING_DIR}" cmake --install "${BUILD_DIR}" --strip

# ----- Build RPM package -----
mkdir -p "${DIST_DIR}"
gem install fpm --no-document 2>/dev/null || true

# RPM (RHEL 8/9, AlmaLinux, Rocky Linux)
fpm -s dir -t rpm \
	-n yosys \
	-v "${VERSION}" \
	--iteration 1 \
	--architecture x86_64 \
	--description "Yosys Open SYnthesis Suite - RTL synthesis framework" \
	--url "https://yosyshq.net/yosys/" \
	--license ISC \
	--maintainer yosys-build \
	--rpm-os linux \
	--depends readline \
	--depends tcl \
	--depends zlib \
	--depends libffi \
	-p "${DIST_DIR}/yosys-${VERSION}-1.el8.x86_64.rpm" \
	-C "${STAGING_DIR}" usr/

# DEB (Ubuntu 18.04+, Debian 10+)
fpm -s dir -t deb \
	-n yosys \
	-v "${VERSION}" \
	--iteration 1 \
	--architecture amd64 \
	--description "Yosys Open SYnthesis Suite - RTL synthesis framework" \
	--url "https://yosyshq.net/yosys/" \
	--license ISC \
	--maintainer yosys-build \
	--depends libreadline7 \
	--depends tcl8.6 \
	--depends zlib1g \
	--depends libffi6 \
	-p "${DIST_DIR}/yosys-${VERSION}-1_amd64.deb" \
	-C "${STAGING_DIR}" usr/

# ----- Print summary -----
echo ""
echo "===== Build complete: yosys ${VERSION} ====="
ls -lh "${DIST_DIR}/"
echo ""
echo "Binary requires:"
echo "  glibc ≥ 2.28 (RHEL 8+)"
echo "  CPU: x86-64-v3 (Haswell 2013+)"
echo ""
echo "Dynamic library dependencies:"
ldd "${STAGING_DIR}/usr/bin/yosys" 2>/dev/null | grep -v 'linux-vdso\|ld-linux\|libstdc++\|libgcc' || true
