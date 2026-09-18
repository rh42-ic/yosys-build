# yosys-build

[Yosys](https://github.com/YosysHQ/yosys) 的自动化 RPM/DEB 构建工程。

## 下载

从 [Releases](https://github.com/rh42-ic/yosys-build/releases) 页面获取预编译包：

- `yosys-{version}-N.el8.x86_64.rpm` + `yosys-python-{version}-N.el8.x86_64.rpm`（RHEL 8/9、AlmaLinux、Rocky Linux）
- `yosys-{version}-N_amd64.deb` + `python3-yosys-{version}-N_amd64.deb`（Ubuntu 20.04+、Debian 10+）
- `yosys-{version}-N-windows-x64.zip`（**Windows 10/11**，便携免安装，零系统依赖）

`yosys-python` / `python3-yosys` 为可选的 Pyosys（Python 3.9 绑定）子包，不装也可正常使用 yosys。

## 兼容性

| 要求 | 最低版本 | 说明 |
| ------ | --------- | ------ |
| **glibc** | ≥ 2.28 | AlmaLinux 8 构建，兼容 RHEL 8+、Ubuntu 20.04+、Debian 10+ |
| **CPU** | x86-64-v3 | Intel Haswell (2013+) / AMD Excavator (2015+)，AVX2/FMA/BMI |
| **RHEL** | 8+ | 主要目标平台 |
| **Ubuntu** | 20.04+ | Ubuntu 18.04 的 glibc 是 2.27，无法运行 |
| **Debian** | 10+ | |
| **Windows** | 10 / 11 x64 | 便携 zip；解压后运行 `start.bat`，全部 DLL 已内置 |

> Windows 包面向 PC 用户，不做老系统兼容；官方（OSS CAD Suite）同样只承诺 Windows 10/11。

### Pyosys 子包说明

Pyosys 模块针对 Python 3.9 编译（ABI 与运行解释器必须一致）：

- RPM `yosys-python`：适用于 RHEL 8/9（AppStream `python39-libs`）
- DEB `python3-yosys`：适用于 Debian 11（`libpython3.9`）
- 其他 Python 版本的系统请使用上游 [PyPI wheels](https://pypi.org/project/yosys/)（官方按 Python 版本分别出包）

## 依赖

### 运行时（包管理器自动安装，主包）

| 库 | RPM 包名 | DEB 包名 |
| ---- | ---------- | ---------- |
| glibc | `glibc >= 2.28` | `libc6 (>= 2.28)` |
| Tcl | `tcl` | `tcl8.6` |
| zlib | `zlib` | `zlib1g` |
| ncurses (termcap) | `ncurses-libs` | `libncursesw6`, `libtinfo6` |

Pyosys 子包额外依赖 `python39-libs`（RPM）/ `libpython3.9`（DEB）。

### 静态链接（已内置，无运行时依赖）

| 组件 | 说明 |
| ------ | ------ |
| libstdc++、libgcc | C/C++ 运行时 |
| readline 8.2 | 交互式命令行（源码自编译，避免 soname 跨发行版不兼容） |
| libffi 3.4.8 | 外部函数接口（源码自编译，与上游 wheels 同款做法） |

| ABC | 逻辑综合引擎 |
| fmt, json11, fst, bigint, slang… | 第三方 bundled 库 |

## 构建参数

| 选项 | 值 | 说明 |
| ------ | ---- | ------ |
| `CMAKE_BUILD_TYPE` | `Release` | 优化编译 |
| `CMAKE_C_COMPILER` | `gcc` | GCC 14 (gcc-toolset-14) |
| `CMAKE_CXX_COMPILER` | `g++` | GCC 14 C++ |
| `CMAKE_INTERPROCEDURAL_OPTIMIZATION` | `ON` | 链接时优化 (LTO) |
| `YOSYS_USE_BUNDLED_LIBS` | `ON` | 使用项目自带第三方库 |
| `BUILD_SHARED_LIBS` | `OFF` | libyosys 编译为静态库 |
| `YOSYS_WITH_PYTHON` | `OFF`（主包）/ `ON`（子包） | 主二进制不链接 libpython；Pyosys 用官方 `YOSYS_BUILD_PYTHON_ONLY` 模式单独构建 |
| `YOSYS_INSTALL_PYTHON_SITEDIR` | `/usr/lib/python3.9/site-packages` | 兼容 EL8 与 Debian 的 purelib 路径 |
| `-march=x86-64-v3` | — | Haswell (2013+)，AVX2/FMA/BMI |
| `-fno-math-errno -fno-trapping-math` | — | 放宽浮点优化 |
| `-static-libgcc -static-libstdc++` | — | 静态链接 C/C++ 运行时 |

## 与上游 yosys 的版本要求对比

| 依赖 | 上游要求 | yosys-build | 降级方式 |
| ------ | --------- | ------------- | --------- |
| glibc | 取决于构建主机 | **≥ 2.28** | AlmaLinux 8 容器编译 |
| CMake | ≥ 3.28 | 3.31（官方二进制） | 不依赖系统 repo |
| Bison | ≥ 3.6 | 3.8.2（自编译） | 自编译安装到 /usr/local |
| Ninja | ≥ 1.10 | 1.12.1（官方二进制） | 多输出 depslog 需要 1.10+ |
| Python | ≥ 3.9 | 3.9（AppStream） | pyosys/generator.py 使用 3.9+ 语法 |
| GCC | C++20 | 14 (gcc-toolset-14) | AppStream 安装 |
| readline | 系统库 | 静态链接 8.2 | 源码自编译，无 soname 依赖 |
| libffi | 系统库 | 静态链接 3.4.8 | 源码自编译，无 soname 依赖 |

所有下载的源码包（CMake、Ninja、Bison、readline、libffi）均校验 SHA256。

## 构建容器

在 `almalinux:8` 容器内编译，自然获得 glibc 2.28 兼容性。

### 编译依赖

| 包 | 来源 | 说明 |
| ---- | ------ | ------ |
| gcc-toolset-14 | AlmaLinux 8 AppStream | C++20 编译器 |
| cmake ≥ 3.28 | [官方二进制](https://github.com/Kitware/CMake/releases) | 构建系统，不依赖系统 repo |
| bison ≥ 3.8 | [GNU FTP](https://ftp.gnu.org/gnu/bison/) | 自编译安装 |
| flex ≥ 2.6 | AppStream | 词法分析器 |
| ninja ≥ 1.10 | [官方二进制](https://github.com/ninja-build/ninja/releases) | 构建后端（多输出 depslog 需要 1.10+） |
| python39 + pybind11/cxxheaderparser | AppStream + pip | Pyosys 代码生成（generator.py 需 ≥ 3.9） |
| readline 8.2 | [GNU FTP](https://ftp.gnu.org/gnu/readline/) | 自编译静态库 |
| libffi 3.4.8 | [GitHub](https://github.com/libffi/libffi/releases) | 自编译静态库 |
| tcl-devel / zlib-devel / ncurses-devel | AppStream | Tcl 脚本 / 压缩 / 终端 |
| ruby + fpm | AppStream + gem | 打 RPM/DEB 包 |

## Windows 构建（MSYS2 MINGW64）

Windows 包在 `windows-latest` runner 的 **MSYS2 MINGW64** 环境中原生构建（与 yosys 官方 CI 的 `mingw-build` job 完全同工具链），打包方式与 OSS CAD Suite 一致：

| 组件 | 来源 | 说明 |
| ---- | ------ | ------ |
| GCC | MSYS2 MINGW64（官方 CI 同款） | 官方 CI 每日验证的构建路径 |
| tcl 8.6 / libffi / zlib / python | MSYS2 mingw-w64-x86_64 包 | 与官方 mingw-build job 的包列表一致 |
| 构建参数 | `-DCMAKE_BUILD_TYPE=Release` | 照抄官方；不开 LTO（LTO 与 MINGW 符号导出冲突） |
| 全部运行时 DLL | `/mingw64/bin/*.dll` 全量拷入 `bin/` | OSS CAD Suite 同款：宁可多带，不漏一个；Windows 加载器只搜索 exe 所在目录，DLL 必须与 exe 同目录 |

Windows 不需要静态链接（Linux 才需要）：zip 内 DLL 全量自带，**零系统依赖**。产物为便携 zip（`yosys-{version}-N-windows-x64.zip`）：`bin/`（yosys.exe、yosys-abc.exe 及全部运行时 DLL）、`share/yosys`（techlibs）、`lib/`（tcl 8.6 数据），附 `start.bat` / `environment.bat` / `environment.ps1` 环境脚本。不含 pyosys（官方 Windows wheel 亦不支持，`.pyd` 命名问题）。

## CI 验证

workflow 在发布前自动执行：

1. `verify-rpm`：在干净的 `almalinux:8` 容器中 `dnf install` 安装 RPM（校验依赖名可从仓库解析），检查 glibc 上限 ≤ 2.28、动态依赖仅为 tcl/zlib/ncursesw，并运行综合冒烟测试
2. `verify-deb`：在 `debian:11` 容器中 `apt-get install` 安装 DEB（含 pyosys 子包），运行综合冒烟测试与 `import pyosys` 测试
3. `verify-win`：在 `windows-latest` 上解压 zip，运行 yosys.exe 综合冒烟测试、Tcl 检查（验证打包的 TCL_LIBRARY）与 yosys-abc，并在仅含 System32 的精简 PATH 下复验自包含性
4. 独立 `release` job：全部构建与验证通过后才发布（rpm + deb + zip 统一 release）

也可通过 **workflow_dispatch** 手动指定 tag 重新构建（如修复打包问题后重发）。

## 本地构建

```bash
docker run --rm -v "$(pwd):/work" -w /work almalinux:8 \
    bash -c "
        bash scripts/install-deps.sh &&
        bash scripts/build.sh v0.69
    "
```

Windows 包在 GitHub Actions 的 `windows-latest` runner（MSYS2 MINGW64）上构建，本地如需复现请参考 workflow 的 `build-win` job。

## 许可

ISC — 与 Yosys 上游一致。
