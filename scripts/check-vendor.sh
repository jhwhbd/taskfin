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
#
# ⚠️ 重要：vendor/ 已被「品牌化改造」（应用名/图标/PWA 启动图统一改为 TaskFIN，
#    见 branding/ 与 scripts/gen-icons.cjs、gen-splash.cjs）。本脚本【不哈希本地文件】，
#    只比对「上游 HEAD 是否前进」，因此你的品牌修改【不会】触发误报；
#    但若上游前进导致「落后」，重新拉取上游会【覆盖品牌文件】，需重跑品牌脚本。
# =============================================================
set -euo pipefail

REPOS=(
  "vikunja|go-vikunja/vikunja|main"
  "ezbookkeeping|mayswind/ezbookkeeping|main"
)

echo "===== vendor 上游源码版本校验 ====="
echo ""
echo "⚠️ 注意：vendor/ 已做品牌化改造（TaskFIN），本脚本只检测『上游是否前进』，"
echo "   不会因你的品牌修改而误报；但上游前进后若重新拉取，会覆盖品牌文件，需重跑品牌脚本。"
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
  # 从 SOURCES.md 取记录的哈希（取 12 位）。标题大小写不定，统一转小写匹配。
  recorded=$(awk -v name="$name" '
    tolower($0) ~ ("^### " tolower(name)) {found=1; next}
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
    echo "      ⚠️  vendor/ 含品牌化修改，直接重新拉取会【覆盖 TaskFIN 品牌文件】！"
    echo "      如需更新上游，请按以下步骤保留品牌："
    echo "        1) git clone --depth 1 https://github.com/$repo.git /tmp/$name"
    echo "        2) 用 /tmp/$name 覆盖 vendor/$name（保留 .git 外的全部文件，注意先备份你的品牌改动）"
    echo "        3) 更新 vendor/SOURCES.md 中的哈希与日期"
    echo "        4) 重新执行品牌化：node scripts/gen-icons.cjs && node scripts/gen-splash.cjs"
    echo "           （必要时再按 README「品牌化」段重改名称字符串）"
  fi
  echo ""
done
echo "===== 校验完毕 ====="
