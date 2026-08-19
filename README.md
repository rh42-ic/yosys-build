# yosys-build

[Yosys](https://github.com/YosysHQ/yosys) 的自动化 RPM/DEB 构建工程。

## 下载

从 [Releases](https://github.com/rh42-ic/yosys-build/releases) 页面获取预编译包：

- `yosys-{version}-1.el8.x86_64.rpm`（RHEL 8/9、AlmaLinux、Rocky Linux）
- `yosys-{version}-1_amd64.deb`（Ubuntu 18.04+、Debian 10+，详见兼容性说明）

## 兼容性

| 要求 | 最低版本 | 说明 |
| ------ | --------- | ------ |
| **glibc** | ≥ 2.28 | AlmaLinux 8 构建，自然兼容 RHEL 8+ |
| **CPU** | x86-64-v3 | Intel Haswell (2013+) / AMD Excavator (2015+)，AVX2/FMA/BMI |
| **RHEL** | 8+ | 主要目标平台 |
| **Ubuntu** | 18.04+ | 可能需要 compat 库，见下方说明 |
| **Debian** | 10+ | 可能需要 compat 库 |

### Ubuntu/Debian 兼容性说明

二进制在 AlmaLinux 8 上编译，链接的 soname 随系统版本。如果 DEB 包安装时提示依赖不满足：

```bash
# Ubuntu 20.04+ 可能需要旧版 readline
sudo apt install libreadline7

# 如果 libffi6 不可用，创建符号链接（通常安全）
# 或从旧版本 repo 安装
```

**建议**：EDA 工作站以 RHEL 8/9 为主，RPM 包开箱即用。

## 依赖

### 运行时（包管理器自动安装）

| 库 | RPM 包名 | DEB 包名 |
| ---- | ---------- | ---------- |
| readline | `readline` | `libreadline7` |
| Tcl | `tcl` | `tcl8.6` |
| zlib | `zlib` | `zlib1g` |
| libffi | `libffi` | `libffi6` |
| Python (Pyosys) | `python39` | `libpython3.9` |

### 静态链接（已内置）

| 组件 | 说明 |
| ------ | ------ |
| libstdc++、libgcc | C/C++ 运行时 |
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
| `YOSYS_WITH_PYTHON` | `ON` | 启用 Pyosys Python 绑定 |
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
| readline | 系统库 | 系统库（动态） | soname 兼容 |

## 构建容器

在 `almalinux:8` 容器内编译，自然获得 glibc 2.28 兼容性。

### 编译依赖

| 包 | 来源 | 说明 |
| ---- | ------ | ------ |
| gcc-toolset-14 | AlmaLinux 8 AppStream | C++20 编译器 |
| cmake ≥ 3.28 | [官方二进制](https://github.com/Kitware/CMake/releases) | 构建系统，不依赖系统 repo |
| bison ≥ 3.8 | [GNU FTP](https://ftp.gnu.org/gnu/bison/) | 自编译安装 |
| flex ≥ 2.6 | AppStream | 词法分析器 |
| ninja ≥ 1.10 | [官方二进制](https://github.com/ninja-build/ninja/releases) | 构建后端（0.68 多输出 depslog 需要 1.10+） |
| python39 + pybind11/cxxheaderparser | AppStream + pip | Pyosys 代码生成（generator.py 需 ≥ 3.9） |
| readline-devel | AppStream | 命令行编辑 |
| tcl-devel | AppStream | Tcl 脚本 |
| zlib-devel | AppStream | 压缩库 |
| libffi-devel | AppStream | 外部函数接口 |
| ruby + fpm | AppStream + gem | 打 RPM/DEB 包 |

## 本地构建

```bash
docker run --rm -v "$(pwd):/work" -w /work almalinux:8 \
    bash -c "
        bash scripts/install-deps.sh &&
        bash scripts/build.sh v0.68
    "
```

## 许可

ISC — 与 Yosys 上游一致。
