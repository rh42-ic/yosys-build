#!/usr/bin/env bash
# Install build dependencies on AlmaLinux 8 / RHEL 8 / Rocky Linux 8
set -euo pipefail

# ----- Enable required repos -----
dnf install -y epel-release dnf-plugins-core
dnf config-manager --set-enabled powertools

# ----- Base toolchain -----
# GitHub runner images are minimal: install everything we may ever need.
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
	xz \
	binutils \
	cpio \
	zstd \
	file \
	ncurses-devel

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
CMAKE_SHA256=5a1133ff103c71eb5120e2cc3de922733e7d8a26a98ae716397e8676adb367bf
if ! cmake --version 2>/dev/null | grep -q "${CMAKE_VERSION}"; then
	curl -fsSL "https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-x86_64.tar.gz" -o /tmp/cmake.tar.gz
	echo "${CMAKE_SHA256}  /tmp/cmake.tar.gz" | sha256sum -c -
	tar xz -C /usr/local --strip-components=1 -f /tmp/cmake.tar.gz
	rm -f /tmp/cmake.tar.gz
fi

# ----- Install Ninja from official binary (repo ninja 1.9 fails on multi-output depslog used by yosys 0.68 pyosys) -----
NINJA_VERSION=1.12.1
NINJA_SHA256=6f98805688d19672bd699fbbfa2c2cf0fc054ac3df1f0e6a47664d963d530255
if ! ninja --version 2>/dev/null | grep -q "${NINJA_VERSION}"; then
	curl -fsSL "https://github.com/ninja-build/ninja/releases/download/v${NINJA_VERSION}/ninja-linux.zip" -o /tmp/ninja-linux.zip
	echo "${NINJA_SHA256}  /tmp/ninja-linux.zip" | sha256sum -c -
	unzip -o /tmp/ninja-linux.zip -d /usr/local/bin
	rm -f /tmp/ninja-linux.zip
	ninja --version
fi

# ----- Enable GCC 14 for all subsequent compilation -----
source /opt/rh/gcc-toolset-14/enable

# ----- Compile Bison 3.8+ from source (repo has 3.0.4) -----
BISON_VERSION=3.8.2
BISON_SHA256=9bba0214ccf7f1079c5d59210045227bcf619519840ebfa80cd3849cff5a5bf2
if ! bison --version 2>/dev/null | grep -q "${BISON_VERSION}"; then
	curl -fsSL "https://ftp.gnu.org/gnu/bison/bison-${BISON_VERSION}.tar.xz" -o /tmp/bison.tar.xz
	echo "${BISON_SHA256}  /tmp/bison.tar.xz" | sha256sum -c -
	tar xJ -C /tmp -f /tmp/bison.tar.xz
	pushd "/tmp/bison-${BISON_VERSION}"
	./configure --prefix=/usr/local
	make -j"$(nproc)"
	make install
	popd
	ldconfig
	rm -rf "/tmp/bison-${BISON_VERSION}" /tmp/bison.tar.xz
fi

# ----- Readline 8.2, statically linked -----
# readline's soname differs across target distros (libreadline.so.7 on EL8, .so.8 on
# Ubuntu 20.04+/Debian 11+), so we build it from source and link it statically.
# yosys links readline through pkg-config, which ignores Libs.private, so we install
# our own readline.pc with the static archive (and its termcap dependency) in Libs.
READLINE_VERSION=8.2
READLINE_SHA256=3feb7171f16a84ee82ca18a36d7b9be109a52c04f492a053331d7d1095007c35
if [ ! -f /usr/local/lib/libreadline.a ]; then
	curl -fsSL "https://ftp.gnu.org/gnu/readline/readline-${READLINE_VERSION}.tar.gz" -o /tmp/readline.tar.gz
	echo "${READLINE_SHA256}  /tmp/readline.tar.gz" | sha256sum -c -
	tar xz -C /tmp -f /tmp/readline.tar.gz
	pushd "/tmp/readline-${READLINE_VERSION}"
	# -fPIC: libreadline.a is also linked into the shared pyosys module (libyosys.so)
	CFLAGS="-fPIC -O3" ./configure --prefix=/usr/local --disable-shared --enable-static --with-curses
	make -j"$(nproc)"
	make install
	popd
	rm -rf "/tmp/readline-${READLINE_VERSION}" /tmp/readline.tar.gz
	cat >/usr/local/lib/pkgconfig/readline.pc <<'EOF'
prefix=/usr/local
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include

Name: Readline
Description: GNU Readline library (statically linked)
Version: 8.2
# Use -lreadline (not an absolute path to libreadline.a): CMake's
# pkg_check_modules places absolute-path archives before the object
# files on the link line, where a static archive is never consulted.
# /usr/local/lib has no libreadline.so (built --disable-shared), so
# -lreadline resolves to the static archive.
Libs: -L${libdir} -lreadline -lncursesw -ltinfo
Cflags: -I${includedir}
EOF
fi

# ----- libffi 3.4.8, statically linked (same approach as upstream YosysHQ wheels) -----
# libffi's soname also differs across target distros (libffi.so.6 on EL8/Debian 10,
# .so.7 on Debian 11/Ubuntu 20.04, .so.8 on Ubuntu 22.04), so static it is.
LIBFFI_VERSION=3.4.8
LIBFFI_SHA256=bc9842a18898bfacb0ed1252c4febcc7e78fa139fd27fdc7a3e30d9d9356119b
if [ ! -f /usr/local/lib/libffi.a ]; then
	curl -fsSL "https://github.com/libffi/libffi/releases/download/v${LIBFFI_VERSION}/libffi-${LIBFFI_VERSION}.tar.gz" -o /tmp/libffi.tar.gz
	echo "${LIBFFI_SHA256}  /tmp/libffi.tar.gz" | sha256sum -c -
	tar xz -C /tmp -f /tmp/libffi.tar.gz
	pushd "/tmp/libffi-${LIBFFI_VERSION}"
	# -fPIC: libffi.a is also linked into the shared pyosys module (libyosys.so)
	CFLAGS="-fPIC -O3" ./configure --prefix=/usr/local --disable-shared --enable-static --disable-docs
	make -j"$(nproc)"
	make install
	popd
	rm -rf "/tmp/libffi-${LIBFFI_VERSION}" /tmp/libffi.tar.gz
	# Keep the pkg-config file as generated: it already uses `-L${toolexeclibdir} -lffi`.
	# The absolute-path form would be placed before the objects by CMake's
	# pkg_check_modules (static archive never consulted -> undefined refs).
	# -lffi resolves to libffi.a because --disable-shared left no libffi.so.
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
echo "readline: $(PKG_CONFIG_PATH=/usr/local/lib/pkgconfig pkg-config --modversion readline) (static)"
echo "libffi: $(PKG_CONFIG_PATH=/usr/local/lib/pkgconfig pkg-config --modversion libffi) (static)"
