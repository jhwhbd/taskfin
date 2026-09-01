#!/usr/bin/env bash
# =============================================================
# 任务财务系统 — 一键部署脚本（宿主机 / 群晖 SSH 执行）
# 功能：
#   1. 复制 .env.example -> .env（若不存在），提醒填真实值
#   2. 创建运行时数据目录
#   3. 按 PUID/PGID 赋权（群晖适配）
#   4. 从 vendor/ 源码构建 Vikunja / ezBookkeeping 品牌化镜像
#   5. 拉起全部服务
#   6. 运行 check-config.sh 做部署前自检（密钥占位符 + webhook 三处一致）
#   7. 打印仍需手动完成的事项清单
# 用法：在仓库根目录执行  bash scripts/deploy.sh
# =============================================================
set -euo pipefail

# 项目目录（脚本位于 <项目>/scripts/ 下，自动推导）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

echo "===== TaskFIN 一键部署 ====="
echo "项目目录: $PROJECT_DIR"

# ---------- 1. .env ----------
if [ ! -f "$PROJECT_DIR/.env" ]; then
  echo "[1/6] 未发现 .env，已从 .env.example 复制模板"
  cp "$PROJECT_DIR/.env.example" "$PROJECT_DIR/.env"
  echo "  ⚠️ 请先编辑 .env 填好真实值（DOMAIN / QQ_EMAIL / QQ_AUTH_CODE /"
  echo "     EZB_SECRET_KEY / WEBHOOK_SECRET / N8N_ENCRYPTION_KEY），再重新运行本脚本。"
  exit 0
fi
echo "[1/6] .env 已存在，复用"

# 载入 .env 中的 PUID/PGID/TZ（仅按需提取已知键，不整体 source .env，
# 避免 .env 内特殊字符被当作 shell 执行，#8）
_PICK() { grep -E "^${1}=" "$PROJECT_DIR/.env" 2>/dev/null | head -1 | cut -d= -f2- ; }
PUID="$(_PICK PUID)"; PUID="${PUID:-1000}"
PGID="$(_PICK PGID)"; PGID="${PGID:-1000}"
TZ="$(_PICK TZ)"; TZ="${TZ:-Asia/Shanghai}"

# ---------- 2. 数据目录 ----------
echo "[2/6] 创建运行时数据目录 ..."
mkdir -p data/npm/data data/npm/letsencrypt data/ddns-go \
         data/vikunja/files data/vikunja/db \
         data/ezbookkeeping/data data/ezbookkeeping/storage \
         data/n8n data/backup_staging

# ---------- 3. 赋权（群晖适配） ----------
echo "[3/6] 按 PUID:PGID=$PUID:$PGID 赋权 ..."
chown -R "$PUID:$PGID" \
  data/ezbookkeeping/data data/ezbookkeeping/storage \
  data/vikunja/files data/vikunja/db \
  data/n8n data/backup_staging || {
    echo "  ⚠️ chown 失败（可能权限不足）；若在群晖请确认以有 sudo 权限用户运行。"
  }

# ---------- 4. 部署前自检（前置，避免配置错误浪费构建/启动，#8）----------
if [ -x "$SCRIPT_DIR/check-config.sh" ]; then
  echo "[4/6] 运行部署前自检 ..."
  bash "$SCRIPT_DIR/check-config.sh" || { echo "  ❌ 自检未通过，请先按上方提示修正后再部署。"; exit 1; }
else
  echo "[4/6] 跳过自检（未找到 check-config.sh）"
fi

# ---------- 5. 构建品牌化镜像 ----------
echo "[5/6] 从 vendor/ 源码构建 Vikunja / ezBookkeeping 镜像（首次较慢，请耐心）..."
docker compose build vikunja ezbookkeeping

# ---------- 6. 拉起服务 ----------
echo "[6/6] 启动全部服务 ..."
docker compose up -d

# ---------- 7. 后续手动事项 ----------
cat <<'EOF'

============================================================
部署已完成，以下仍需你手动完成（不可自动化）：
============================================================
1. n8n 初始化：浏览器打开 flow.<你的域名> → 注册 Owner 账号并设置强密码。
2. 导入工作流：n8n → Workflows → Import from File，逐个导入 n8n/*.json。
   必开：vikunja-task-sync / vikunja-budget-plan / ezbookkeeping-poll
   选开：ezbookkeeping-recur-tag（周期扣款闭环）、ezbookkeeping-bill-reminder（账单邮件提醒）
3. 配置 Vikunja 两个 Webhook（任务→n8n），建议用 Basic Auth：
   用户名填 taskfin，密码填 .env 的 WEBHOOK_SECRET；
   Target URL 末尾可仍带 ?secret=<WEBHOOK_SECRET> 作兼容（单源：值来自 .env WEBHOOK_SECRET，
   compose 已注入 n8n 容器环境变量，Auth Guard 直接读 $env.WEBHOOK_SECRET）。
4. bill-reminder 工作流：在 n8n 创建一个 SMTP 凭据（类型 smtp，命名"QQ SMTP"），
   填 smtp.qq.com:465(SSL)、用户 <QQ_EMAIL>@qq.com、密码 <QQ_AUTH_CODE>；
   该工作流已挂"Send Email (QQ SMTP)"节点，启用后每日 09:00 发到期提醒。
5. 备份 / 监控：在群晖任务计划加入 scripts/backup.sh（建议每周）与 scripts/monitor.sh（建议每 15 分钟），
   并设置 TASKFIN_ALERT_URL（n8n 告警 webhook 或 IM 机器人地址）以接收失败/异常通知。
6. NPM：在 127.0.0.1:81（或 SSH 隧道）配置三个反代（tasks/fin/flow），申请 SSL 证书；
   设独立强密码（勿复用）。
============================================================
EOF
