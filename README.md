# yosys-build

[Yosys](https://github.com/YosysHQ/yosys) 的自动化 RPM/DEB 构建工程。

## 下载

从 [Releases](https://github.com/rh42-ic/yosys-build/releases) 页面获取预编译包：

- `yosys-{version}-1.x86_64.rpm`（Fedora / RHEL / openSUSE）
- `yosys-{version}-1_amd64.deb`（Debian / Ubuntu 24.04+）

## 构建参数

| 选项 | 值 | 说明 |
| ------ | ----- | ------ |
| `CMAKE_BUILD_TYPE` | `Release` | 优化编译 |
| `CMAKE_C_COMPILER` | `clang` | Clang 编译器 |
| `CMAKE_CXX_COMPILER` | `clang++` | Clang C++ 编译器 |
| `CMAKE_INTERPROCEDURAL_OPTIMIZATION` | `ON` | 链接时优化 (LTO) |
| `YOSYS_USE_BUNDLED_LIBS` | `ON` | 使用项目自带第三方库 |
| `BUILD_SHARED_LIBS` | `OFF` | libyosys 编译为静态库 |
| `-march=x86-64-v3` | — | 目标指令集 Haswell (2013+)，启用 AVX2/FMA/BMI |
| `-fno-math-errno -fno-trapping-math` | — | 放宽浮点优化约束 |
| `-static-libgcc -static-libstdc++` | — | 静态链接 C/C++ 运行时 |

## 静态链接策略

完全静态链接（`-static`）在 glibc 下不可靠（NSS/DNS 依赖动态加载）。采取折中：

| 层级 | 链接方式 |
| ------ | --------- |
| C/C++ 运行时 (libstdc++, libgcc) | 静态 |
| Yosys 自带库 (ABC, fmt, json11, fst…) | 静态 |
| 系统库 (readline, Tcl, zlib, libffi) | 动态，由包管理器处理 |

## 依赖

### 编译依赖

| 包 | 说明 |
| ---- | ------ |
| clang (C++20) | 编译器 |
| cmake ≥ 3.28 | 构建系统 |
| ninja-build | 构建后端 |
| bison ≥ 3.8 | 语法解析器生成器 |
| flex | 词法分析器 |
| python3 ≥ 3.11 | 代码生成 |
| libreadline-dev | 命令行编辑 |
| libffi-dev | 外部函数接口 |
| tcl-dev | Tcl 脚本 |
| zlib1g-dev | 压缩库 |

### 运行时依赖

| 库 | RPM | DEB |
| ---- | ----- | ----- |
| readline | `readline` | `libreadline8t64` |
| Tcl | `tcl` | `tcl8.6` |
| zlib | `zlib` | `zlib1g` |
| libffi | `libffi` | `libffi8` |

## 兼容性

二进制在 Ubuntu 24.04 (glibc 2.39) 上编译，需要 glibc ≥ 2.39（Ubuntu 24.04+、Fedora 39+、RHEL 10+）。CPU 需支持 x86-64-v3（Haswell 2013+）。

## 许可

ISC — 与 Yosys 上游一致。
