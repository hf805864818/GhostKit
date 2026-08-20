# GhostKit RootHelper 修复指南

## 问题诊断

你安装的 `GhostKit-v1.0.16 2.tipa` 中的 RootHelper 二进制存在两个问题：

1. **架构错误**: 32-bit ARM (`cffaedfe`)，但 iOS 17 需要 64-bit ARM (`cafebabe`)
2. **签名缺失**: 没有通过 `ldid` 签名嵌入 entitlements，导致 AMFI 拒绝执行

## 功能影响

| 安装方式 | 可用功能 | 状态 |
|---------|---------|------|
| 仅 .tipa (TrollStore) | RootHelper 路径 (14个命令) | ❌ 全部失效 |
| 仅 .deb (越狱) | Tweak 路径 (37个功能) | ✅ 完全可用 |
| .tipa + .deb | 双通道 | ✅ 完全可用 |

## 修复方案

### 方案一：修复现有 tipa（推荐，如果你有 Mac）

```bash
# 1. 安装 ldid
brew install ldid

# 2. 运行修复脚本
cd /path/to/GhostKit
./fix_roothelper.sh GhostKit-v1.0.16\ 2.tipa GhostKit_fixed.tipa

# 3. 安装修复后的 tipa
# 卸载原版本 → 安装 GhostKit_fixed.tipa
```

### 方案二：重新编译 RootHelper（完整修复）

```bash
# 1. 安装 Xcode Command Line Tools
xcode-select --install

# 2. 编译 64-bit RootHelper
./build_roothelper.sh

# 3. 修复签名
./fix_roothelper.sh GhostKit-v1.0.16\ 2.tipa GhostKit_fixed.tipa

# 4. 安装
```

### 方案三：同时安装 .deb（最简单）

```bash
# 1. 通过 Sileo/Verbor 安装 GhostKit.deb
# 2. 重启设备
# 3. 功能完全可用
```

## 技术细节

### RootHelper 工作原理

```
App (Swift) → posix_spawn → RootHelper (C binary) → root 操作
     ↓              ↓
  Darwin Notify    需要:
  (Tweak 路径)     1. 64-bit arm64e 架构
                   2. 有效的 code signature
                   3. 嵌入的 entitlements
```

### 为什么 32-bit 不行？

- iOS 11+ 在 A11 芯片 (iPhone Xs 及更新) 上不支持 32-bit 应用
- iOS 15+ 完全弃用 32-bit
- 你的设备是 arm64e (64-bit)，无法执行 32-bit 二进制

### 为什么需要签名？

- TrollStore 安装的 app 有特殊 entitlements
- RootHelper 需要这些 entitlements 才能执行 root 操作
- `ldid -S<entitlements>` 将 entitlements 嵌入到 code signature 中
- AMFI (Apple Mobile File Integrity) 会验证签名

## 验证修复

修复后验证：

```bash
# 检查架构
xxd -p -l 4 RootHelper
# 应该输出: cafebabf (64-bit)

# 检查签名
ldid -v RootHelper
# 应该显示 CodeDirectory 信息

# 检查 entitlements
ldid -e RootHelper
# 应该显示 <key>run-unsigned-code</key> 等权限
```

## 快速对比

| 操作 | 修复前 | 修复后 |
|-----|-------|-------|
| Keychain 清理 | ❌ 报错 | ✅ 成功 |
| IDFA 刷新 | ❌ 报错 | ✅ 成功 |
| 一键新机 | ❌ 报错 | ✅ 成功 |
| 缓存清理 | ❌ 报错 | ✅ 成功 |
| 设置面板 | ✅ 可用 | ✅ 可用 |
| App Store 账号 | ⚠️ 检测不到 | ⚠️ 检测不到 |

## 注意事项

1. **RootHelper 必须签名**，否则 `posix_spawn` 返回 errno=13 (EACCES)
2. **架构必须是 arm64e**，否则 iOS 无法执行
3. **Tweak 路径不需要 RootHelper**，但需要 .deb 安装
4. **Apple ID 检测**需要额外修复（已修复，见 AccountListView.swift）

## 后续维护

如果以后重新编译：

```bash
# 编译 RootHelper
./build_roothelper.sh

# 替换 tipa 中的 RootHelper
unzip GhostKit-v1.0.16.tipa -d /tmp/ghk
cp RootHelper /tmp/ghk/Payload/GhostKitApp.app/RootHelper
chmod +x /tmp/ghk/Payload/GhostKitApp.app/RootHelper
cd /tmp/ghk && zip -rq GhostKit_new.tipa Payload/
```
