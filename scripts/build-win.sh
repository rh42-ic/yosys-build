#!/usr/bin/env bash
# Build yosys for Windows x86_64 inside the MSYS2 MINGW64 environment and
# package a portable zip.
#
# The build mirrors yosys' own official CI job (.github/workflows/extra-builds.yml,
# mingw-build): MSYS2 MINGW64, distro packages (tcl 8.6, libffi, zlib...), plain
# Release cmake with no LTO (LTO conflicts with MINGW --export-all-symbols).
# ALL runtime DLLs are bundled next to the executables in bin/ (same directory
# as the exes), so the zip has zero system dependencies.
set -euo pipefail

TAG="${1:?Usage: $0 <yosys-git-tag>}"
VERSION="${TAG#v}"
# Package iteration: bump when repackaging the same upstream version
ITERATION=1

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}/.."
BUILD_DIR="${ROOT_DIR}/build-win"
STAGING_DIR="${ROOT_DIR}/staging-win"
PKG_DIR="${ROOT_DIR}/pkg-win"
DIST_DIR="${ROOT_DIR}/dist"
SRC_DIR="${ROOT_DIR}/yosys-src"
PKG_ROOT_DIR="yosys-${VERSION}-win64"

# ----- Clone yosys (shared with the Linux build script) -----
if [ ! -d "${SRC_DIR}" ]; then
	git clone --branch "${TAG}" \
		--depth 1 --recurse-submodules --shallow-submodules \
		https://github.com/YosysHQ/yosys.git "${SRC_DIR}"
fi

# ----- Configure and build (same options as the official mingw-build CI job) -----
# Windows needs no static linking (unlike the Linux packages): every runtime
# DLL is bundled next to the executables in bin/, so the zip has zero system
# dependencies.
rm -rf "${BUILD_DIR}"
cmake -S "${SRC_DIR}" -B "${BUILD_DIR}" \
	-DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_C_FLAGS=-w \
	-DCMAKE_CXX_FLAGS=-w \
	-DYOSYS_WITH_PYTHON=OFF

# Build quietly: third-party code (ABC...) emits lots of GCC warnings/notes.
# Log to a file; only show the tail on failure.
if ! cmake --build "${BUILD_DIR}" -j"$(nproc)" >/tmp/yosys-build-win.log 2>&1; then
	echo "FAIL: yosys build failed, last lines of the log:"
	tail -n 120 /tmp/yosys-build-win.log
	exit 1
fi

# ----- Install to staging -----
# Use --prefix (not DESTDIR): MSYS2 rewrites an absolute /usr/local prefix to
# the MSYS2 install root, and DESTDIR then glues the two paths together
# (staging-win/<msys2-root>/usr/local/...). --prefix is the install root
# directly; the POSIX path is converted for the Windows cmake by MSYS2 as
# usual, and installs land flat in <staging>/bin, <staging>/share, ...
rm -rf "${STAGING_DIR}"
cmake --install "${BUILD_DIR}" --strip --prefix "${STAGING_DIR}"

# ----- Assemble portable package -----
rm -rf "${PKG_DIR}"
mkdir -p "${PKG_DIR}/${PKG_ROOT_DIR}/bin"
mkdir -p "${PKG_DIR}/${PKG_ROOT_DIR}/lib"
mkdir -p "${PKG_DIR}/${PKG_ROOT_DIR}/share"

# Executables and techlibs. yosys (MINGW, YOSYS_WIN32_UNIX_DIR) locates
# share/ relative to the exe: <exe>/share or <exe>/../share/yosys
cp "${STAGING_DIR}/bin/"*.exe "${PKG_DIR}/${PKG_ROOT_DIR}/bin/"
cp -r "${STAGING_DIR}/share/yosys" "${PKG_DIR}/${PKG_ROOT_DIR}/share/"

# ALL MINGW64 runtime DLLs (copy everything, miss nothing). They must sit next
# to the exes in bin/: the Windows loader searches the exe's own directory, not
# a sibling lib/ (lib/ holds only Tcl library data).
shopt -s nullglob
cp /mingw64/bin/*.dll "${PKG_DIR}/${PKG_ROOT_DIR}/bin/"
shopt -u nullglob

# Tcl library data (init.tcl, encodings, msgcat...) for the bundled tcl DLL
# (data only; tcl86.dll itself is in bin/)
cp -r /mingw64/lib/tcl8.6 "${PKG_DIR}/${PKG_ROOT_DIR}/lib/"

# Environment launchers and README
cat >"${PKG_DIR}/${PKG_ROOT_DIR}/environment.bat" <<'EOF'
@echo off
rem Add yosys to PATH and point Tcl at the bundled library data
set "YOSYS_ROOT=%~dp0"
set "PATH=%YOSYS_ROOT%bin;%YOSYS_ROOT%lib;%PATH%"
set "TCL_LIBRARY=%YOSYS_ROOT%lib\tcl8.6"
EOF

cat >"${PKG_DIR}/${PKG_ROOT_DIR}/environment.ps1" <<'EOF'
# Add yosys to PATH and point Tcl at the bundled library data
$env:YOSYS_ROOT = Split-Path -Parent $MyInvocation.MyCommand.Path
$env:PATH = "$env:YOSYS_ROOT\bin;$env:YOSYS_ROOT\lib;$env:PATH"
$env:TCL_LIBRARY = "$env:YOSYS_ROOT\lib\tcl8.6"
EOF

cat >"${PKG_DIR}/${PKG_ROOT_DIR}/start.bat" <<'EOF'
@echo off
cmd /k "%~dp0environment.bat"
EOF

cat >"${PKG_DIR}/${PKG_ROOT_DIR}/README.md" <<EOF
# Yosys ${VERSION} (Windows x64)

Portable build for Windows 10/11 (x86_64). No installer, no system
dependencies: everything needed is inside this directory.

## Usage

Double-click \`start.bat\` (or run \`environment.bat\`) to open a shell with
\`yosys\` on PATH, then:

    yosys -p "synth -top top" top.v

Or call the binary directly from any shell:

    bin\\yosys.exe -V

## Features

- yosys driver, yosys-abc, full techlibs, Tcl 8.6 (SDC support)
- All runtime DLLs bundled (zero system dependencies)
- No Python bindings (pyosys is Linux-only in this project)

## Layout

| Path                | Contents                              |
|---------------------|---------------------------------------|
| bin\\yosys.exe      | main binary                           |
| bin\\yosys-abc.exe  | ABC logic synthesis engine            |
| bin\\*.dll          | bundled MinGW runtime DLLs            |
| share\\yosys        | techlibs, plugins data                |
| lib\\tcl8.6         | Tcl 8.6 library data                  |

Built from [YosysHQ/yosys ${TAG}](https://github.com/YosysHQ/yosys/releases/tag/${TAG})
with MSYS2 MINGW64 (GCC), same toolchain as yosys' official CI.
EOF

# ----- Verify: every non-system DLL must be bundled in bin/ -----
# (the copy-all step above already provides them; this guards against a DLL
# that lives outside /mingw64/bin)
SYSTEM_DLLS='KERNEL32.dll USER32.dll GDI32.dll ADVAPI32.dll SHELL32.dll ole32.dll OLEAUT32.dll WS2_32.dll NETAPI32.dll msvcrt.dll VERSION.dll COMDLG32.dll SHLWAPI.dll WINMM.dll IMM32.dll UxTheme.dll dwmapi.dll IPHLPAPI.dll CRYPT32.dll RPCRT4.dll SETUPAPI.dll COMCTL32.dll WINSPOOL.DRV WLDAP32.dll DNSAPI.dll SECUR32.dll NTDLL.DLL api-ms-win- ext-ms-win-' # typos:ignore-line (Windows API/DLL names)

check_binary_dlls() {
	local bin="$1"
	echo "--- DLL dependencies of $(basename "$bin") ---"
	local deps
	deps=$(objdump -p "$bin" | awk '/DLL Name:/{print $3}')
	echo "$deps"
	while read -r dll; do
		[ -z "$dll" ] && continue
		in_system=false
		for pat in $SYSTEM_DLLS; do
			if [[ "$dll" == "$pat"* ]]; then
				in_system=true
				break
			fi
		done
		if ! $in_system && [ ! -f "${PKG_DIR}/${PKG_ROOT_DIR}/bin/$dll" ]; then
			echo "FAIL: $bin needs $dll but it is not bundled in bin/"
			exit 1
		fi
	done <<<"$deps"
	echo "OK: $(basename "$bin") runtime dependencies are satisfied"
}

check_binary_dlls "${PKG_DIR}/${PKG_ROOT_DIR}/bin/yosys.exe"
check_binary_dlls "${PKG_DIR}/${PKG_ROOT_DIR}/bin/yosys-abc.exe"

# ----- Package -----
mkdir -p "${DIST_DIR}"
rm -f "${DIST_DIR}/yosys-${VERSION}-${ITERATION}-windows-x64.zip"
cd "${PKG_DIR}"
zip -qr "${DIST_DIR}/yosys-${VERSION}-${ITERATION}-windows-x64.zip" "${PKG_ROOT_DIR}"
cd "${ROOT_DIR}"

echo "=== Windows package ==="
ls -lh "${DIST_DIR}/yosys-${VERSION}-${ITERATION}-windows-x64.zip"
