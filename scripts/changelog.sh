#!/bin/bash
#
# changelog.sh - GhostKit 更新日志生成脚本
#
# 从 git log 获取提交记录，按 commit 类型分类，
# 生成格式化的 CHANGELOG.md（新版本在顶部）。
#
# 用法:
#   ./scripts/changelog.sh                    # 使用 VERSION 文件中的版本号
#   ./scripts/changelog.sh 1.2.0              # 指定版本号
#   ./scripts/changelog.sh 1.2.0 --no-commit   # 指定版本号，不自动 git commit
#
# 分类规则:
#   feat:     -> ✨ 新功能
#   fix:      -> 🐛 问题修复
#   其他       -> 📦 其他变更
#

set -euo pipefail

# ── 路径配置 ──────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
VERSION_FILE="${PROJECT_DIR}/VERSION"
CHANGELOG_FILE="${PROJECT_DIR}/CHANGELOG.md"
TEMP_FILE="${PROJECT_DIR}/CHANGELOG.tmp.md"

# ── 颜色输出 ──────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }
debug()   { echo -e "${BLUE}[DEBUG]${NC} $*"; }

# ── 获取版本号 ───────────────────────────────────────────
get_version() {
    if [[ -n "${1:-}" ]]; then
        echo "$1"
        return
    fi

    if [[ ! -f "${VERSION_FILE}" ]]; then
        error "VERSION 文件不存在: ${VERSION_FILE}"
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

# ── 获取当前日期 (YYYY-MM-DD) ───────────────────────────
get_date() {
    date '+%Y-%m-%d'
}

# ── 获取上一个版本标签 ──────────────────────────────────
# 用于确定 git log 的范围：从上一个版本标签到 HEAD
get_last_tag() {
    # 获取最新的 git tag（按版本号排序）
    local last_tag
    last_tag=$(git -C "${PROJECT_DIR}" tag --sort=-v:refname 2>/dev/null | head -n 1 || true)

    if [[ -n "${last_tag}" ]]; then
        echo "${last_tag}"
    else
        # 没有找到任何 tag，返回空字符串
        echo ""
    fi
}

# ── 获取提交记录 ────────────────────────────────────────
# 参数: $1 - 起始 ref (上一个 tag)，为空则获取所有提交
# 返回格式: <type>|<subject>
get_commits() {
    local last_tag="$1"
    local range

    if [[ -n "${last_tag}" ]]; then
        range="${last_tag}..HEAD"
        info "获取提交记录范围: ${range}"
    else
        range="HEAD"
        info "获取全部提交记录"
    fi

    # 提取每个提交的 subject 行，格式为 "type: description"
    # 使用 %s 获取 subject，%H 获取完整 hash（用于去重）
    git -C "${PROJECT_DIR}" log "${range}" --no-merges \
        --pretty=format:"%s" 2>/dev/null || true
}

# ── 分类提交记录 ────────────────────────────────────────
# 将提交按类型分类输出到数组
classify_commits() {
    local commits="$1"

    # 临时文件用于存储分类后的提交
    local feat_file
    local fix_file
    local other_file
    feat_file=$(mktemp)
    fix_file=$(mktemp)
    other_file=$(mktemp)

    # 按行处理每个提交
    while IFS= read -r line; do
        [[ -z "${line}" ]] && continue

        # 提取类型前缀（冒号前的部分，转为小写）
        local type
        type=$(echo "${line}" | sed -n 's/^\([a-zA-Z]*\):.*/\1/p' | tr '[:upper:]' '[:lower:]')

        local subject
        subject=$(echo "${line}" | sed 's/^[a-zA-Z]*:[[:space:]]*//')

        case "${type}" in
            feat)
                echo "- ${subject}" >> "${feat_file}"
                ;;
            fix)
                echo "- ${subject}" >> "${fix_file}"
                ;;
            *)
                # 保留原始的 commit message
                echo "- ${line}" >> "${other_file}"
                ;;
        esac
    done <<< "${commits}"

    # 输出分类结果到全局变量
    FEAT_COMMITS=$(cat "${feat_file}")
    FIX_COMMITS=$(cat "${fix_file}")
    OTHER_COMMITS=$(cat "${other_file}")

    rm -f "${feat_file}" "${fix_file}" "${other_file}"
}

# ── 生成新版本日志段落 ──────────────────────────────────
generate_version_section() {
    local version="$1"
    local date="$2"

    local section=""
    section+="## v${version} - ${date}"
    section+=$'\n'

    # 新功能
    section+=$'\n'
    section+="### ✨ 新功能"
    section+=$'\n'
    if [[ -n "${FEAT_COMMITS}" ]]; then
        section+="${FEAT_COMMITS}"
        section+=$'\n'
    else
        section+="- (无)"
        section+=$'\n'
    fi

    # 问题修复
    section+=$'\n'
    section+="### 🐛 问题修复"
    section+=$'\n'
    if [[ -n "${FIX_COMMITS}" ]]; then
        section+="${FIX_COMMITS}"
        section+=$'\n'
    else
        section+="- (无)"
        section+=$'\n'
    fi

    # 其他变更
    section+=$'\n'
    section+="### 📦 其他变更"
    section+=$'\n'
    if [[ -n "${OTHER_COMMITS}" ]]; then
        section+="${OTHER_COMMITS}"
        section+=$'\n'
    else
        section+="- (无)"
        section+=$'\n'
    fi

    echo "${section}"
}

# ── 合并到 CHANGELOG.md ────────────────────────────────
merge_changelog() {
    local new_section="$1"

    # 读取现有 CHANGELOG.md 的头部（# 更新日志 + 描述）
    local header=""
    if [[ -f "${CHANGELOG_FILE}" ]]; then
        # 提取标题和描述行（在第一个 ## 之前的内容）
        header=$(awk '/^## / {exit} {print}' "${CHANGELOG_FILE}")
    fi

    # 如果没有头部，创建默认头部
    if [[ -z "${header}" ]]; then
        header=$'# 更新日志\n\n所有显著变更都会记录在此文件中。\n'
    fi

    # 提取现有版本段落（第一个 ## 之后的所有内容）
    local existing_versions=""
    if [[ -f "${CHANGELOG_FILE}" ]]; then
        existing_versions=$(awk '/^## / {p=1} p' "${CHANGELOG_FILE}")
    fi

    # 组装新的 CHANGELOG.md：头部 + 新版本段落 + 现有版本段落
    {
        echo "${header}"
        echo ""
        echo "${new_section}"
        echo ""
        if [[ -n "${existing_versions}" ]]; then
            echo "${existing_versions}"
        fi
    } > "${CHANGELOG_FILE}"

    # 去除可能多余的空行
    # 使用 sed 压缩连续空行为单个空行
    sed -i '/^$/N;/^\n$/D' "${CHANGELOG_FILE}" 2>/dev/null || true
}

# ── 自动提交更改 ────────────────────────────────────────
auto_commit() {
    local version="$1"
    info "自动提交 CHANGELOG.md 更新..."

    cd "${PROJECT_DIR}"

    # 配置 git（如果未配置）
    git config user.name "${GITHUB_ACTOR:-"GhostKit Bot"}" 2>/dev/null || true
    git config user.email "${GITHUB_ACTOR:-"ghostkit"}@users.noreply.github.com" 2>/dev/null || true

    git add CHANGELOG.md VERSION 2>/dev/null || true

    if git diff --cached --quiet 2>/dev/null; then
        info "没有更改需要提交"
        return 0
    fi

    git commit -m "docs(changelog): 更新日志 v${version}" 2>/dev/null || true
    info "已提交 CHANGELOG.md 更新"
}

# ── 主逻辑 ──────────────────────────────────────────────
main() {
    local version=""
    local do_commit="yes"

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --no-commit)
                do_commit="no"
                shift
                ;;
            --help|-h)
                cat << 'EOF'
GhostKit 更新日志生成脚本

用法:
  ./scripts/changelog.sh                    # 使用 VERSION 文件中的版本号
  ./scripts/changelog.sh 1.2.0              # 指定版本号
  ./scripts/changelog.sh 1.2.0 --no-commit   # 指定版本号，不自动提交

选项:
  --no-commit    生成日志但不执行 git commit
  --help, -h     显示帮助信息

分类规则:
  feat:    -> ✨ 新功能
  fix:     -> 🐛 问题修复
  其他      -> 📦 其他变更
EOF
                exit 0
                ;;
            *)
                version="$1"
                shift
                ;;
        esac
    done

    # 获取版本号
    version=$(get_version "${version}")
    local date
    date=$(get_date)

    info "生成更新日志: v${version} (${date})"

    # 获取提交记录
    local last_tag
    last_tag=$(get_last_tag)
    if [[ -n "${last_tag}" ]]; then
        info "上一个版本标签: ${last_tag}"
    else
        info "未找到历史版本标签，将获取全部提交"
    fi

    local commits
    commits=$(get_commits "${last_tag}")

    if [[ -z "${commits}" ]]; then
        warn "没有找到提交记录"
        commits="chore: 初始提交"
    fi

    # 分类提交记录
    info "分类提交记录..."
    classify_commits "${commits}"

    local feat_count fix_count other_count
    feat_count=$(echo "${FEAT_COMMITS}" | grep -c "^-" 2>/dev/null || echo 0)
    fix_count=$(echo "${FIX_COMMITS}" | grep -c "^-" 2>/dev/null || echo 0)
    other_count=$(echo "${OTHER_COMMITS}" | grep -c "^-" 2>/dev/null || echo 0)

    info "提交分类统计: 新功能 ${feat_count} | 修复 ${fix_count} | 其他 ${other_count}"

    # 生成新版本日志段落
    local new_section
    new_section=$(generate_version_section "${version}" "${date}")

    # 合并到 CHANGELOG.md
    info "更新 CHANGELOG.md..."
    merge_changelog "${new_section}"

    info "CHANGELOG.md 已更新: ${CHANGELOG_FILE}"

    # 自动提交
    if [[ "${do_commit}" == "yes" ]]; then
        auto_commit "${version}"
    fi

    info "更新日志生成完成!"
}

main "$@"
