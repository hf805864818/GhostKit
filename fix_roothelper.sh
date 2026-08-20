#!/bin/bash
#
# fix_roothelper.sh - 修复 RootHelper 签名和架构问题
#
# 用法:
#   ./fix_roothelper.sh <input.tipa> [output.tipa]
#
# 前置要求:
#   - macOS + Xcode Command Line Tools
#   - ldid (brew install ldid)
#   - Theos SDK (可选，用于重新编译)
#

set -e

INPUT_TIPA="${1:?用法: $0 <input.tipa> [output.tipa]}"
OUTPUT_TIPA="${2:-$(dirname "$INPUT_TIPA")/GhostKit_fixed.tipa}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "==> GhostKit RootHelper 修复工具"
echo "    输入: $INPUT_TIPA"
echo "    输出: $OUTPUT_TIPA"
echo ""

# 检查 ldid
if ! command -v ldid &> /dev/null; then
    echo "❌ 错误: ldid 未安装"
    echo "    安装: brew install ldid"
    exit 1
fi
echo "✓ ldid 已安装: $(which ldid)"

# 检查 entitlements
ENTITLEMENTS="$SCRIPT_DIR/App/GhostKitApp/Entitlements/GhostKit.entitlements"
if [ ! -f "$ENTITLEMENTS" ]; then
    echo "❌ 错误: 找不到 $ENTITLEMENTS"
    exit 1
fi
echo "✓ Entitlements 文件已找到"

# 解压 tipa
TEMP_DIR=$(mktemp -d)
echo ""
echo "==> 解压 tipa..."
unzip -q "$INPUT_TIPA" -d "$TEMP_DIR"

APP_BUNDLE=$(find "$TEMP_DIR" -name "*.app" -type d | head -n 1)
if [ -z "$APP_BUNDLE" ]; then
    echo "❌ 错误: 找不到 .app bundle"
    exit 1
fi
echo "✓ 找到 bundle: $APP_BUNDLE"

# 检查 RootHelper
ROOTHELPER="$APP_BUNDLE/RootHelper"
if [ ! -f "$ROOTHELPER" ]; then
    echo "❌ 错误: RootHelper 二进制不存在"
    echo "    可能需要在 Xcode 中先编译 RootHelper"
    exit 1
fi

# 检查架构
echo ""
echo "==> 检查 RootHelper 架构..."
MAGIC=$(xxd -p -l 4 "$ROOTHELPER" 2>/dev/null || echo "unknown")
case "$MAGIC" in
    cafebabf)
        echo "  ✓ 架构正确: 64-bit ARM"
        ARCH_OK=true
        ;;
    cffaedfe)
        echo "  ⚠ 架构错误: 32-bit ARM (需要 64-bit)"
        echo "    需要重新编译 RootHelper 为 arm64e"
        ARCH_OK=false
        ;;
    *)
        echo "  ? 未知架构: $MAGIC"
        ARCH_OK=false
        ;;
esac

# 检查签名
echo ""
echo "==> 检查代码签名..."
if ldid -v "$ROOTHELPER" 2>/dev/null | grep -q "CodeDirectory"; then
    echo "  ✓ RootHelper 已有签名"
    HAS_SIG=true
else
    echo "  ⚠ RootHelper 缺少签名"
    HAS_SIG=false
fi

# 修复签名
if [ "$HAS_SIG" = false ]; then
    echo ""
    echo "==> 修复签名..."
    ldid -S"$ENTITLEMENTS" "$ROOTHELPER"
    echo "  ✓ RootHelper 已签名并嵌入 entitlements"
    
    # 同时签名主程序
    MAIN_BIN=$(ls "$APP_BUNDLE" | grep -v RootHelper | grep -v ldid | grep -v insert_dylib | grep -v ct_bypass | grep -v trollstore | grep -v '\.dylib$' | head -n 1)
    if [ -n "$MAIN_BIN" ]; then
        ldid -S"$ENTITLEMENTS" "$APP_BUNDLE/$MAIN_BIN"
        echo "  ✓ 主程序已签名"
    fi
fi

# 如果架构不对，提示需要重新编译
if [ "$ARCH_OK" = false ]; then
    echo ""
    echo "⚠ 警告: RootHelper 是 32-bit 架构，iOS 17 无法执行"
    echo ""
    echo "修复方法："
    echo "  1. 安装 Theos: brew install theos"
    echo "  2. 编译 RootHelper:"
    echo "     cd App/GhostKitApp/RootHelper/"
    echo "     clang -arch arm64e -framework Foundation -O2 RootHelper.c -o RootHelper"
    echo "  3. 签名:"
    echo "     ldid -S ../Entitlements/GhostKit.entitlements RootHelper"
    echo "  4. 替换 tipa 中的 RootHelper 并重新打包"
    echo ""
    echo "继续打包（签名已修复，但架构问题仍存在）..."
fi

# 打包
echo ""
echo "==> 重新打包 tipa..."
cd "$TEMP_DIR"
rm -f "$OUTPUT_TIPA"
zip -rq "$OUTPUT_TIPA" Payload/

# 清理
rm -rf "$TEMP_DIR"

echo ""
echo "✓ 完成!"
echo "    输出: $OUTPUT_TIPA"
echo ""
if [ "$ARCH_OK" = false ]; then
    echo "⚠ 注意: RootHelper 仍是 32-bit 架构，需要重新编译为 64-bit"
    echo "    在 iOS 17 设备上可能仍然无法运行"
fi
