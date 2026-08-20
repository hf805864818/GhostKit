#!/bin/bash
#
# build_roothelper.sh - 编译 RootHelper 为 64-bit arm64e
#
# 用法:
#   ./build_roothelper.sh [output_dir]
#
# 前置要求:
#   - Xcode Command Line Tools
#   - iOS SDK (通过 Xcode 或 Theos 安装)
#

set -e

OUTPUT_DIR="${1:-.}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE="$SCRIPT_DIR/App/GhostKitApp/RootHelper/RootHelper.c"
HEADER="$SCRIPT_DIR/App/GhostKitApp/RootHelper/RootHelper.h"

echo "==> 编译 RootHelper (64-bit arm64e)"
echo "    源码: $SOURCE"
echo "    输出: $OUTPUT_DIR/RootHelper"
echo ""

# 检查 Xcode
if ! command -v xcrun &> /dev/null; then
    echo "❌ 错误: 未找到 xcrun，请安装 Xcode Command Line Tools"
    echo "    xcode-select --install"
    exit 1
fi

# 查找 iOS SDK
SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || echo "")
if [ -z "$SDK_PATH" ]; then
    echo "❌ 错误: 未找到 iOS SDK"
    exit 1
fi
echo "✓ iOS SDK: $SDK_PATH"

# 检查源码
if [ ! -f "$SOURCE" ]; then
    echo "❌ 错误: 找不到源码 $SOURCE"
    exit 1
fi

# 编译
echo ""
echo "==> 编译中..."
clang \
    -arch arm64e \
    -isysroot "$SDK_PATH" \
    -mios-version-min=16.0 \
    -framework Foundation \
    -O2 \
    -Wall \
    "$SOURCE" \
    -o "$OUTPUT_DIR/RootHelper"

if [ -f "$OUTPUT_DIR/RootHelper" ]; then
    echo "✓ 编译成功"
    
    # 检查架构
    MAGIC=$(xxd -p -l 4 "$OUTPUT_DIR/RootHelper")
    case "$MAGIC" in
        cafebabf)
            echo "✓ 架构正确: 64-bit ARM (arm64e)"
            ;;
        *)
            echo "⚠ 警告: 未知架构 $MAGIC"
            ;;
    esac
    
    # 检查大小
    SIZE=$(stat -f%z "$OUTPUT_DIR/RootHelper" 2>/dev/null || stat -c%s "$OUTPUT_DIR/RootHelper" 2>/dev/null)
    echo "✓ 文件大小: $SIZE bytes"
    
    # 签名
    ENTITLEMENTS="$SCRIPT_DIR/App/GhostKitApp/Entitlements/GhostKit.entitlements"
    if [ -f "$ENTITLEMENTS" ]; then
        echo ""
        echo "==> 签名中..."
        if command -v ldid &> /dev/null; then
            ldid -S"$ENTITLEMENTS" "$OUTPUT_DIR/RootHelper"
            echo "✓ RootHelper 已签名"
        else
            echo "⚠ 警告: ldid 未安装，跳过签名"
            echo "    安装: brew install ldid"
        fi
    else
        echo "⚠ 警告: 未找到 entitlements 文件"
    fi
    
    echo ""
    echo "✓ 完成!"
    echo "    输出: $OUTPUT_DIR/RootHelper"
else
    echo "❌ 编译失败"
    exit 1
fi
