#!/bin/bash
#
# version.sh - GhostKit 版本号管理脚本
#
# 用法:
#   ./scripts/version.sh current          # 显示当前版本号
#   ./scripts/version.sh bump-patch        # patch 版本号 +1 (e.g. 1.0.0 -> 1.0.1)
#   ./scripts/version.sh bump-minor       # minor 版本号 +1, patch 归零 (e.g. 1.0.0 -> 1.1.0)
#   ./scripts/version.sh bump-major       # major 版本号 +1, minor/patch 归零 (e.g. 1.0.0 -> 2.0.0)
#   ./scripts/version.sh set <version>    # 设置为指定版本号
#

set -euo pipefail

# ── 路径配置 ──────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
VERSION_FILE="${PROJECT_DIR}/VERSION"

# ── 颜色输出 ──────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }
debug()   { echo -e "${BLUE}[DEBUG]${NC} $*"; }

# ── 读取当前版本号 ────────────────────────────────────────
# 从 VERSION 文件读取版本号，去除首尾空白
read_version() {
    if [[ ! -f "${VERSION_FILE}" ]]; then
        error "VERSION 文件不存在: ${VERSION_FILE}"
        error "请先创建 VERSION 文件，内容如: 1.0.0"
        exit 1
    fi

    local version
    version=$(tr -d '[:space:]' < "${VERSION_FILE}")

    if [[ -z "${version}" ]]; then
        error "VERSION 文件为空"
        exit 1
    fi

    echo "${version}"
}

# ── 写入版本号 ────────────────────────────────────────────
write_version() {
    local version="$1"
    echo "${version}" > "${VERSION_FILE}"
    info "版本号已更新为: ${version}"
}

# ── 验证版本号格式 (MAJOR.MINOR.PATCH) ──────────────────
validate_version() {
    local version="$1"
    if ! echo "${version}" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
        error "版本号格式错误: ${version}"
        error "正确格式: MAJOR.MINOR.PATCH (例如: 1.0.0)"
        exit 1
    fi
}

# ── 解析版本号各部分 ─────────────────────────────────────
# 使用 IFS='.' 将版本号拆分为 MAJOR MINOR PATCH
parse_version() {
    local version="$1"
    IFS='.' read -r MAJOR MINOR PATCH <<< "${version}"
}

# ── 显示当前版本号 ───────────────────────────────────────
cmd_current() {
    local version
    version=$(read_version)
    info "当前版本号: ${version}"
    echo "${version}"
}

# ── bump patch 版本号 ────────────────────────────────────
# 1.0.0 -> 1.0.1
cmd_bump_patch() {
    local version
    version=$(read_version)
    validate_version "${version}"
    parse_version "${version}"

    PATCH=$((PATCH + 1))
    local new_version="${MAJOR}.${MINOR}.${PATCH}"
    write_version "${new_version}"
    info "patch 版本号升级: ${version} -> ${new_version}"
    echo "${new_version}"
}

# ── bump minor 版本号 ────────────────────────────────────
# 1.0.0 -> 1.1.0
cmd_bump_minor() {
    local version
    version=$(read_version)
    validate_version "${version}"
    parse_version "${version}"

    MINOR=$((MINOR + 1))
    PATCH=0
    local new_version="${MAJOR}.${MINOR}.${PATCH}"
    write_version "${new_version}"
    info "minor 版本号升级: ${version} -> ${new_version}"
    echo "${new_version}"
}

# ── bump major 版本号 ────────────────────────────────────
# 1.0.0 -> 2.0.0
cmd_bump_major() {
    local version
    version=$(read_version)
    validate_version "${version}"
    parse_version "${version}"

    MAJOR=$((MAJOR + 1))
    MINOR=0
    PATCH=0
    local new_version="${MAJOR}.${MINOR}.${PATCH}"
    write_version "${new_version}"
    info "major 版本号升级: ${version} -> ${new_version}"
    echo "${new_version}"
}

# ── 设置指定版本号 ───────────────────────────────────────
cmd_set() {
    local version="$1"
    validate_version "${version}"
    write_version "${version}"
    info "版本号已设置为: ${version}"
    echo "${version}"
}

# ── 显示帮助信息 ────────────────────────────────────────
show_help() {
    cat << 'EOF'
GhostKit 版本号管理脚本

用法:
  ./scripts/version.sh current            显示当前版本号
  ./scripts/version.sh bump-patch         patch 版本号 +1 (1.0.0 -> 1.0.1)
  ./scripts/version.sh bump-minor         minor 版本号 +1 (1.0.0 -> 1.1.0)
  ./scripts/version.sh bump-major         major 版本号 +1 (1.0.0 -> 2.0.0)
  ./scripts/version.sh set <version>      设置为指定版本号 (如 set 2.1.0)

版本号格式: MAJOR.MINOR.PATCH (语义化版本规范)

示例:
  ./scripts/version.sh current             # 输出: 1.0.0
  ./scripts/version.sh bump-patch          # 输出: 1.0.1
  ./scripts/version.sh bump-minor          # 输出: 1.1.0
  ./scripts/version.sh bump-major          # 输出: 2.0.0
  ./scripts/version.sh set 3.2.1           # 输出: 3.2.1
EOF
}

# ── 主逻辑 ──────────────────────────────────────────────
main() {
    local command="${1:-}"
    shift || true

    case "${command}" in
        current)
            cmd_current
            ;;
        bump-patch)
            cmd_bump_patch
            ;;
        bump-minor)
            cmd_bump_minor
            ;;
        bump-major)
            cmd_bump_major
            ;;
        set)
            if [[ $# -lt 1 ]]; then
                error "缺少版本号参数"
                error "用法: ./scripts/version.sh set <version>"
                exit 1
            fi
            cmd_set "$1"
            ;;
        help|--help|-h)
            show_help
            ;;
        "")
            error "未指定命令"
            show_help
            exit 1
            ;;
        *)
            error "未知命令: ${command}"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
