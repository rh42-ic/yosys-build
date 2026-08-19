#!/usr/bin/env bash
# Install build dependencies on AlmaLinux 8 / RHEL 8 / Rocky Linux 8
set -euo pipefail

# ----- Enable required repos -----
dnf install -y epel-release dnf-plugins-core
dnf config-manager --set-enabled powertools

# ----- Base toolchain -----
dnf install -y \
	gcc-toolset-14-gcc \
	gcc-toolset-14-gcc-c++ \
	gcc-toolset-14-binutils \
	flex \
	git \
	make \
	m4 \
	unzip \
	pkgconfig \
	python39 \
	python39-devel \
	python39-pip \
	ruby \
	rubygems \
	tar \
	xz

# ----- Build-time libraries -----
dnf install -y \
	readline-devel \
	tcl-devel \
	zlib-devel \
	libffi-devel

# ----- Packaging tools (rpmbuild for RPM, dpkg-dev from EPEL for DEB) -----
dnf install -y \
	rpm-build \
	dpkg-dev

# ----- Python deps for Pyosys (yosys FindPyosysEnv requires pybind11 + cxxheaderparser on the host interpreter; pyosys/generator.py needs Python >= 3.9) -----
python3.9 -m pip install --no-cache-dir 'pybind11>=3,<4' cxxheaderparser

# ----- Install CMake from official binary (repo CMake 3.20 is too old) -----
CMAKE_VERSION=3.31.6
if ! cmake --version 2>/dev/null | grep -q "${CMAKE_VERSION}"; then
	curl -fsSL "https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-x86_64.tar.gz" |
		tar xz -C /usr/local --strip-components=1
fi

# ----- Install Ninja from official binary (repo ninja 1.9 fails on multi-output depslog used by yosys 0.68 pyosys) -----
NINJA_VERSION=1.12.1
if ! ninja --version 2>/dev/null | grep -q "${NINJA_VERSION}"; then
	curl -fsSL "https://github.com/ninja-build/ninja/releases/download/v${NINJA_VERSION}/ninja-linux.zip" -o /tmp/ninja-linux.zip
	unzip -o /tmp/ninja-linux.zip -d /usr/local/bin
	rm -f /tmp/ninja-linux.zip
	ninja --version
fi

# ----- Enable GCC 14 for all subsequent compilation -----
source /opt/rh/gcc-toolset-14/enable

# ----- Compile Bison 3.8+ from source (repo has 3.0.4) -----
BISON_VERSION=3.8.2
if ! bison --version 2>/dev/null | grep -q "${BISON_VERSION}"; then
	curl -fsSL "https://ftp.gnu.org/gnu/bison/bison-${BISON_VERSION}.tar.xz" |
		tar xJ
	pushd "bison-${BISON_VERSION}"
	./configure --prefix=/usr/local
	make -j$(nproc)
	make install
	popd
	ldconfig
	rm -rf "bison-${BISON_VERSION}"
fi

# ----- fpm for packaging (v1.15 last to support Ruby 2.5) -----
gem install fpm -v '~> 1.15.0' --no-document

echo '=== Build environment ready ==='
gcc --version | head -1
g++ --version | head -1
cmake --version | head -1
bison --version | head -1
flex --version | head -1
python3.9 --version
python3.9 -m pybind11 --version
