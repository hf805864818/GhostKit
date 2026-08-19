# GhostKit

> iOS 越狱环境下的一站式设备隐私管理工具，集成了 Keychain 管理、标识符变更、缓存清理、应用管理、游戏画质配置等功能。

[![CI/CD](https://github.com/user/GhostKit/actions/workflows/ci.yml/badge.svg)](https://github.com/user/GhostKit/actions/workflows/ci.yml)
[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](https://github.com/user/GhostKit/releases)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-iOS%2015%2B-lightgrey.svg)]()

---

## 目录

- [简介](#简介)
- [功能列表](#功能列表)
- [支持的 iOS 版本和越狱方式](#支持的-ios-版本和越狱方式)
- [安装方法](#安装方法)
- [使用说明](#使用说明)
- [开发环境要求](#开发环境要求)
- [CI/CD 说明](#cicd-说明)
- [Commit 规范](#commit-规范)
- [项目结构](#项目结构)

---

## 简介

GhostKit 是一款专为 iOS 越狱设备设计的多功能管理工具。它将 Keychain 管理、设备标识符变更、缓存清理、应用管理等功能整合到一个应用中，帮助用户轻松管理设备隐私和清理系统垃圾。

项目基于 Theos 越狱开发框架，支持 roothide/RELAXIN 越狱环境，同时提供 TrollStore 兼容的 .tipa 安装包。

---

## 功能列表

GhostKit 包含 **29 项功能**，涵盖设备管理的各个方面：

### Keychain 管理（6 项）

| # | 功能 | 描述 |
|---|------|------|
| 1 | 清理 Keychain | 一键清除所有 Keychain 数据 |
| 2 | 深度清理 Keychain | 深度清除包括系统级 Keychain 数据 |
| 3 | 删除 Keychains | 指定删除特定 Keychain 条目 |
| 4 | 恢复 Keychains | 从备份中恢复 Keychain 数据 |
| 5 | 备份 Keychains | 将当前 Keychain 数据备份到本地 |
| 6 | 安全关闭本程序 | 安全退出应用，确保数据完整性 |

### 标识符管理（3 项）

| # | 功能 | 描述 |
|---|------|------|
| 7 | 刷新标识符 | 重新生成设备标识符 (IDFA) |
| 8 | 变更新标识符 | 将标识符变更为指定值 |
| 9 | 显示当前标识符 | 查看当前设备的各种标识符信息 |

### 一键新机（1 项）

| # | 功能 | 描述 |
|---|------|------|
| 10 | 一键新机 | 一键重置设备所有标识信息（Keychain + 标识符 + 缓存） |

### 缓存清理（5 项）

| # | 功能 | 描述 |
|---|------|------|
| 11 | 清理系统残留 | 清除系统级临时文件和残留数据 |
| 12 | 清理数据库缓存 | 清理应用数据库缓存文件 |
| 13 | 清理数据目录 | 清除应用数据目录 |
| 14 | 清理 Cookie | 清除系统 Cookie 数据 |
| 15 | 清理粘贴板 | 清除系统粘贴板内容 |

### 应用管理（3 项）

| # | 功能 | 描述 |
|---|------|------|
| 16 | 应用列表 | 查看设备上所有已安装应用 |
| 17 | 应用搜索 | 按名称或标识符搜索应用 |
| 18 | 应用卸载 | 卸载指定应用 |

### 账号管理（1 项）

| # | 功能 | 描述 |
|---|------|------|
| 19 | App Store 账号管理 | 管理 App Store 登录账号 |

### 权限管理（1 项）

| # | 功能 | 描述 |
|---|------|------|
| 20 | 一键允许粘贴 | 为所有应用一键开启粘贴板权限 |

### 游戏画质配置（3 项）

| # | 功能 | 描述 |
|---|------|------|
| 21 | PUBG 流畅画质 | 为 PUBG Mobile 配置低画质以提升帧率 |
| 22 | PUBG 平衡画质 | 为 PUBG Mobile 配置中画质 |
| 23 | PUBG 极致画质 | 为 PUBG Mobile 配置高画质 |

### 其他工具（6 项）

| # | 功能 | 描述 |
|---|------|------|
| 24 | 设备信息 | 查看设备硬件和系统信息 |
| 25 | 画质配置 | 通用游戏画质配置入口 |
| 26 | RootHelper 提权 | 使用 RootHelper 工具获取 root 权限 |
| 27 | 设置 | 应用设置页面 |
| 28 | roothide/RELAXIN 适配 | 支持 roothide 和 RELAXIN 越狱 |
| 29 | TrollStore .tipa 支持 | 提供 TrollStore 兼容的 .tipa 安装包 |

---

## 支持的 iOS 版本和越狱方式

### iOS 版本

| iOS 版本 | 支持状态 |
|----------|----------|
| iOS 15.0 - 15.8 | 完全支持 |
| iOS 16.0 - 16.6 | 完全支持 |
| iOS 17.0 - 17.7 | 完全支持 |
| iOS 18.0+ | 完全支持 |

### 越狱方式

| 越狱方式 | 支持状态 | 安装格式 |
|----------|----------|----------|
| roothide (Hidden Jailbreak) | 完全支持 | .deb |
| RELAXIN | 完全支持 | .deb |
| TrollStore | 完全支持 | .tipa |
| Dopamine | 完全支持 | .deb |
| Palera1n | 完全支持 | .deb |
| NekoJB | 完全支持 | .deb |

---

## 安装方法

### 方法一：通过 .deb 安装（越狱环境）

适用于已越狱设备（roothide、RELAXIN 等）：

1. 从 [Releases](https://github.com/user/GhostKit/releases) 页面下载最新 `GhostKit-v*.deb` 文件
2. 将 deb 文件传输到 iOS 设备
3. 使用以下任一方式安装：
   - **Filza**：用 Filza 文件管理器找到 deb 文件，点击安装
   - **SSH**：通过 SSH 将文件传到设备，执行 `dpkg -i GhostKit-v*.deb`
   - **Sileo / Zebra**：通过包管理器安装

```bash
# 通过 SSH 安装
scp GhostKit-v1.0.0.deb root@<设备IP>:/var/root/
ssh root@<设备IP> "dpkg -i /var/root/GhostKit-v1.0.0.deb && killall -9 SpringBoard"
```

4. 安装完成后，SpringBoard 会自动重启，桌面出现 GhostKit 图标

### 方法二：通过 .tipa 安装（TrollStore）

适用于安装了 TrollStore 的设备：

1. 从 [Releases](https://github.com/user/GhostKit/releases) 页面下载最新 `GhostKit-v*.tipa` 文件
2. 将 .tipa 文件传输到 iOS 设备
3. 在文件管理器中长按 .tipa 文件，选择「分享」->「TrollStore」
4. TrollStore 会自动打开并提示安装
5. 点击「Install」完成安装

---

## 使用说明

### 基本操作

1. **打开 GhostKit**：在桌面点击 GhostKit 图标启动应用
2. **功能导航**：通过主页面的功能列表选择所需功能
3. **执行操作**：点击对应功能按钮执行操作
4. **确认操作**：危险操作（如清理 Keychain）会弹出确认对话框

### 功能详细说明

#### Keychain 管理

- **清理 Keychain**：清除应用相关的 Keychain 数据，适用于需要重新登录的场景
- **深度清理 Keychain**：比普通清理更彻底，清除包括系统级 Keychain
- **备份 Keychains**：在执行清理前建议先备份，以便后续恢复
- **恢复 Keychains**：从备份文件恢复 Keychain 数据

#### 一键新机

一键执行以下所有操作：
- 清理所有 Keychain
- 号新设备标识符（IDFA）
- 清理所有缓存
- 清理 Cookie
- 清理粘贴板

执行后设备将呈现为"全新设备"状态。

#### 游戏画质配置

- 支持 PUBG Mobile、王者荣耀等热门游戏
- 提供三种预设：流畅（低画质高帧率）、平衡（中画质）、极致（高画质）
- 配置文件位于 `game_configs/` 目录
- 应用配置后需重启游戏生效

### 设置

在设置页面可以：
- 切换显示语言（中文/英文）
- 查看版本信息
- 配置 RootHelper 路径
- 管理自动清理规则

---

## 开发环境要求

### 必要工具

| 工具 | 版本要求 | 用途 |
|------|----------|------|
| macOS | 14.0+ (Sonoma) | 编译环境 |
| Xcode | 16.0+ | SDK 和编译工具链 |
| Theos (roothide) | 最新版 | 越狱插件编译框架 |
| ldid | 最新版 | 代码签名伪造 |
| dpkg | 最新版 | .deb 打包工具 |
| make | 最新版 | 构建工具 |

### 安装开发环境

```bash
# 1. 安装 Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 2. 安装依赖
brew install ldid dpkg make

# 3. 安装 roothide Theos
git clone --recursive https://github.com/roothide/theos.git ~/theos
export THEOS=~/theos

# 4. 下载 iOS SDK
cd ~/theos/sdks
# 从 https://github.com/theos/sdks 下载对应版本的 SDK

# 5. 克隆项目
git clone https://github.com/user/GhostKit.git
cd GhostKit

# 6. 编译
make package FINALPACKAGE=1
```

### 编译产物

| 产物 | 说明 | 编译命令 |
|------|------|----------|
| `.deb` | 越狱环境安装包 | `make package FINALPACKAGE=1` |
| `.tipa` | TrollStore 安装包 | `xcodebuild + zip` |

---

## CI/CD 说明

GhostKit 使用 GitHub Actions 实现自动化 CI/CD 流程。

### 工作流

#### 1. 主 CI/CD 工作流 (`.github/workflows/ci.yml`)

**触发条件：**
- push 到 main 分支
- 打 `v*` tag
- 手动触发（可指定版本号）

**流水线流程：**

```
┌─────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────┐
│   prepare   │────>│  build-deb   │────>│   release    │
│  确定版本号  │     │  编译 .deb   │     │  发布 Release │
│  生成日志   │     └──────────────┘     │  上传产物     │
│  提交更新   │     ┌──────────────┐     │              │
└─────────────┘     │  build-tipa  │────>└──────────┘
                    │  编译 .tipa  │
                    └──────────────┘
```

**Job 说明：**

| Job | 运行环境 | 功能 |
|-----|----------|------|
| prepare | ubuntu-latest | 确定版本号、生成更新日志、提交 VERSION 和 CHANGELOG |
| build-deb | macos-14 | 安装 Theos、下载 iOS SDK、编译 .deb 包 |
| build-tipa | macos-14 | Xcode 编译 App、打包为 .tipa |
| release | ubuntu-latest | 下载所有产物、创建 GitHub Release |

#### 2. 自动更新日志工作流 (`.github/workflows/auto-changelog.yml`)

**触发条件：** push 到 main 分支（忽略 CHANGELOG.md 和 VERSION 文件变更）

**功能：** 自动从 git log 提取提交记录，分类生成更新日志，自动提交。

### 版本号管理

版本号遵循 [语义化版本](https://semver.org/) 规范：`MAJOR.MINOR.PATCH`

| 版本变更 | 说明 | 命令 |
|----------|------|------|
| Patch | 修复 bug | `./scripts/version.sh bump-patch` |
| Minor | 新增功能 | `./scripts/version.sh bump-minor` |
| Major | 重大变更 | `./scripts/version.sh bump-major` |

### 更新日志

更新日志由 `scripts/changelog.sh` 自动生成，按提交类型分类：

| 类型 | 分类 | 图标 |
|------|------|------|
| `feat:` | 新功能 | ✨ |
| `fix:` | 问题修复 | 🐛 |
| 其他 | 其他变更 | 📦 |

---

## Commit 规范

项目使用 [Conventional Commits](https://www.conventionalcommits.org/) 规范。

### 提交格式

```
<type>(<scope>): <subject>

<body>

<footer>
```

### Type 类型

| Type | 说明 | 示例 |
|------|------|------|
| `feat` | 新功能 | `feat: 添加 Keychain 备份功能` |
| `fix` | Bug 修复 | `fix: 修复 IDFA 刷新失败问题` |
| `docs` | 文档变更 | `docs: 更新 README 安装说明` |
| `style` | 代码格式 | `style: 统一缩进风格` |
| `refactor` | 代码重构 | `refactor: 重构缓存清理模块` |
| `test` | 测试 | `test: 添加 Keychain 管理器单元测试` |
| `chore` | 构建/工具 | `chore: 更新 CI/CD 配置` |
| `ci` | CI 变更 | `ci: 优化编译流程` |
| `perf` | 性能优化 | `perf: 优化应用列表加载速度` |

### Scope 范围（可选）

| Scope | 说明 |
|-------|------|
| `keychain` | Keychain 相关功能 |
| `identifier` | 标识符管理 |
| `cache` | 缓存清理 |
| `app` | 应用管理 |
| `game` | 游戏配置 |
| `roothelper` | RootHelper |
| `ui` | 界面相关 |
| `ci` | CI/CD |
| `build` | 构建系统 |

### 示例

```bash
# 新功能
git commit -m "feat(keychain): 添加深度清理功能"

# Bug 修复
git commit -m "fix(identifier): 修复 IDFA 刷新后未生效的问题"

# 带描述体的提交
git commit -m "feat(cache): 添加数据目录清理功能

- 支持按应用清理数据目录
- 支持批量操作
- 自动检测敏感目录"

# 带 BREAKING CHANGE 的提交
git commit -m "feat!: 重构 Keychain 管理接口

BREAKING CHANGE: Keychain 管理器 API 完全重构，不兼容旧版本"
```

---

## 项目结构

```
GhostKit/
├── .github/
│   └── workflows/
│       ├── ci.yml                    # 主 CI/CD 工作流
│       └── auto-changelog.yml        # 自动更新日志工作流
├── scripts/
│   ├── version.sh                    # 版本号管理脚本
│   └── changelog.sh                  # 更新日志生成脚本
├── App/
│   └── GhostKitApp/
│       ├── en.lproj/
│       │   └── Localizable.strings   # 英文翻译
│       ├── zh-Hans.lproj/
│       │   └── Localizable.strings   # 简体中文
│       ├── zh-HK.lproj/
│       │   └── Localizable.strings   # 繁体中文
│       └── Resources/
│           └── game_configs/
│               ├── supported_games.plist  # 支持的游戏列表
│               ├── pubgm_smooth.ini       # PUBG 流畅画质
│               ├── pubgm_balance.ini       # PUBG 平衡画质
│               └── pubgm_extreme.ini       # PUBG 极致画质
├── VERSION                           # 当前版本号
├── CHANGELOG.md                      # 更新日志
└── README.md                         # 项目说明
```

---

## License

本项目采用 MIT 许可证。详情请见 [LICENSE](LICENSE) 文件。

---

## 致谢

- [Theos](https://github.com/theos/theos) - 越狱插件开发框架
- [roothide](https://github.com/roothide) - Hidden Jailbreak 支持
- [TrollStore](https://github.com/opa334/TrollStore) - 永久签名工具
