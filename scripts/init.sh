#!/usr/bin/env bash
# =============================================================
# 任务财务系统 — 部署后初始化脚本（仅 CLI 步骤，幂等可重跑）
# 作用：固化部署手册 §5 里「纯命令行、无需网页点选」的步骤，
#       减少手误与遗漏。网页操作（token/账号/工作流）仍需人工完成。
#
# 说明：ezBookkeeping 的公开注册已在 docker-compose.yml 通过
#       EBK_SECURITY_ENABLE_REGISTER=false 默认关闭，无需再用 CLI 关；
#       ezB 的 CLI 也不提供 set-setting 子命令，旧脚本里的对应步骤已移除。
#
# 仍需人工在网页完成的（本脚本替代不了，跑完会提示你）：
#   - Vikunja 网页「设置 → API Tokens」新建 token，填 n8n 变量 vikunja_token
#   - ezBookkeeping 网页注册账号、建「现金/存款」账户、建支出/贷款分类、
#     生成 API Token，填 n8n 变量 ezb_*（见 docs/实施部署手册.md §5.2 / §5.3）
#   - n8n 网页 Import 四个工作流 JSON（n8n/*.json）
#
# 用法（环境变量或位置参数均可）：
#   EZB_ADMIN_EMAIL="你@qq.com" EZB_ADMIN_PASS="强密码" \
#     bash /volume1/docker/taskfin/scripts/init.sh
#   或：bash /volume1/docker/taskfin/scripts/init.sh "你@qq.com" "强密码"
# =============================================================
set -euo pipefail

# ---------- 变量（环境变量优先，否则交互提示） ----------
EZB_ADMIN_EMAIL="${EZB_ADMIN_EMAIL:-${1:-}}"
EZB_ADMIN_PASS="${EZB_ADMIN_PASS:-${2:-}}"

if [ -z "$EZB_ADMIN_EMAIL" ]; then
  read -r -p "管理员邮箱 (QQ邮箱，用于 Vikunja/ezB 首账号): " EZB_ADMIN_EMAIL
fi
if [ -z "$EZB_ADMIN_PASS" ]; then
  read -r -s -p "管理员密码: " EZB_ADMIN_PASS
  echo
fi
if [ -z "$EZB_ADMIN_EMAIL" ] || [ -z "$EZB_ADMIN_PASS" ]; then
  echo "错误：邮箱与密码均必填" >&2
  exit 1
fi

# ---------- 1) Vikunja 创建首管理员（部署手册 §5.1 CLI 兜底） ----------
echo "[1/1] 创建 Vikunja 管理员账号 ($EZB_ADMIN_EMAIL) ..."
docker exec vikunja /app/vikunja/vikunja user create \
  --username admin \
  --email "$EZB_ADMIN_EMAIL" \
  --password "$EZB_ADMIN_PASS" \
  && echo "  完成（若提示用户已存在可忽略）" \
  || echo "  警告：创建失败，可能已存在或容器未就绪，请改在网页注册"

echo "===== 初始化 CLI 步骤完成 ====="
echo "接下来请人工完成（网页）："
echo "  1. Vikunja 设置→API Tokens 新建，填 n8n 变量 vikunja_token"
echo "  2. ezBookkeeping 注册/建账户/建分类/生成 Token，填 n8n 变量 ezb_*"
echo "     （公开注册已由 compose 默认关闭，无需额外 CLI 操作）"
echo "  3. n8n 导入 n8n/*.json 四个工作流"

# ---------- 灾难恢复（非初始化，按需手动执行，见 docs/实施部署手册.md §9.2） ----------
# Vikunja 还原：把备份 zip 放进 data/backup_staging/ 后执行：
#   docker exec -i vikunja /app/vikunja/vikunja restore /backup/<vikunja-xxx.zip>
# ezBookkeeping 还原：停容器 → 用备份 *.db 覆盖 data/ezbookkeeping/data/ 下同名文件 → 起容器
