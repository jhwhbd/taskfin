#!/usr/bin/env bash
# =============================================================
# 上游源码版本校验脚本
# 比对 vendor/ 中收录的上游 commit 哈希与 GitHub 当前最新提交，
# 判断 vendor 快照是否落后于上游、是否需要更新。
#
# 用法：bash scripts/check-vendor.sh
# 依赖：git（用于 ls-remote）
# 说明：vendor 目录已去除 .git，本地无法用 git log 查看版本；
#       本脚本通过 GitHub API 比对上游 HEAD 与 SOURCES.md 记录。
# =============================================================
set -euo pipefail

REPOS=(
  "vikunja|go-vikunja/vikunja|main"
  "ezbookkeeping|mayswind/ezbookkeeping|main"
)

echo "===== vendor 上游源码版本校验 ====="
echo ""
for entry in "${REPOS[@]}"; do
  IFS='|' read -r name repo branch <<< "$entry"
  echo "--- $name ($repo) ---"
  # 获取 GitHub 当前分支 HEAD 哈希
  remote_head=$(git ls-remote "https://github.com/$repo.git" "refs/heads/$branch" 2>/dev/null | awk '{print $1}')
  if [ -z "$remote_head" ]; then
    echo "  [警告] 无法获取 $repo:$branch 的最新提交（网络不通或仓库不可达）"
    echo "  跳过。若网络恢复请重跑本脚本。"
    echo ""
    continue
  fi
  # 从 SOURCES.md 取记录的哈希（取 12 位）
  recorded=$(awk -v name="$name" '
    $0 ~ "^### " name {found=1; next}
    found && /^### / {found=0}
    found && /Vendor 版本/ {
      match($0, /[0-9a-f]{12,}/); print substr($0, RSTART, 12); exit
    }
  ' vendor/SOURCES.md)
  if [ -z "$recorded" ]; then
    echo "  [警告] 无法从 vendor/SOURCES.md 读取 $name 的记录哈希"
    echo ""
    continue
  fi
  remote_short="${remote_head:0:12}"
  if [ "$recorded" = "$remote_short" ]; then
    echo "  ✅ 一致。vendor 快照与上游 $branch 最新提交对齐（$remote_short）。"
  else
    echo "  ⚠️  落后。vendor 记录 $recorded，上游 $branch 最新为 $remote_short"
    echo "      如需更新：git clone --depth 1 https://github.com/$repo.git /tmp/$name \\"
    echo "                 && rm -rf /tmp/$name/.git vendor/$name && cp -r /tmp/$name vendor/$name \\"
    echo "                 && 更新 vendor/SOURCES.md 中的哈希与日期"
  fi
  echo ""
done
echo "===== 校验完毕 ====="
