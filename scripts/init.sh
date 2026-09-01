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
#   - Vikunja 网页「设置 → API Tokens」新建 token，其值与 EZB_* 等写入 .env，由 compose 注入 n8n（$env.VIKUNJA_TOKEN 等；社区版不支持 n8n 内建 Variables，见部署手册 §5.3）
#   - ezBookkeeping 网页注册账号、建「现金/存款」账户、建支出/贷款分类、
#     生成 API Token，写入 .env 后由 compose 注入 n8n（$env.EZB_*，见部署手册 §5.2 / §5.3）
#   - n8n 网页 Import 五个工作流 JSON（n8n/*.json）
#
# 用法（环境变量或位置参数均可）：
#   EZB_ADMIN_EMAIL="你@qq.com" EZB_ADMIN_PASS="强密码" \
#     bash /volume1/docker/taskfin/scripts/init.sh
#   或：bash /volume1/docker/taskfin/scripts/init.sh "你@qq.com" "强密码"
#   可选：VIKUNJA_ADMIN_USER="admin"（默认 admin）指定首管理员用户名；
#        WEBHOOK_SECRET 在 .env 中设置（见 .env.example），脚本会校验其占位符。
# =============================================================
set -euo pipefail

# 项目目录（用于定位 .env 做占位符校验）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ---------- 变量（环境变量优先，否则交互提示） ----------
EZB_ADMIN_EMAIL="${EZB_ADMIN_EMAIL:-${1:-}}"
EZB_ADMIN_PASS="${EZB_ADMIN_PASS:-${2:-}}"
VIKUNJA_ADMIN_USER="${VIKUNJA_ADMIN_USER:-admin}"

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

# ---------- 0) .env 占位符校验（P10，仅警告不阻断） ----------
ENV_FILE="$PROJECT_DIR/.env"
if [ -f "$ENV_FILE" ]; then
  echo "[0/1] 校验 .env 占位符 ..."
  _qq=$(grep -E '^QQ_AUTH_CODE=' "$ENV_FILE" | head -1 | cut -d= -f2-)
  _ezb=$(grep -E '^EZB_SECRET_KEY=' "$ENV_FILE" | head -1 | cut -d= -f2-)
  _wh=$(grep -E '^WEBHOOK_SECRET=' "$ENV_FILE" | head -1 | cut -d= -f2-)
  check_env() {
    local key="$1" val="$2" hint="$3"
    if [ -z "$val" ] || echo "$val" | grep -qiE "yourdomain|10001|xxxx|replace-with|change-me|example"; then
      echo "  ⚠️  .env 的 $key 疑似未修改占位符（$hint）"
    fi
  }
  check_env "QQ_AUTH_CODE" "$_qq" "16 位 QQ 授权码"
  check_env "EZB_SECRET_KEY" "$_ezb" "openssl rand -base64 32 生成的随机密钥"
  check_env "WEBHOOK_SECRET" "$_wh" "openssl rand -hex 16 生成的 webhook 密钥（.env 设置后由 compose 注入 n8n，作为 \$env.WEBHOOK_SECRET，无需在 n8n 内单独建变量，见 check-config.sh 同步点 2）"
  echo "  校验完成（仅警告，不阻断）。"
else
  echo "[0/1] 未找到 $ENV_FILE，跳过占位符校验（你可能在网页/环境变量中直接配置）。"
fi

# ---------- 1) Vikunja 创建首管理员（部署手册 §5.1 CLI 兜底） ----------
echo "[1/1] 创建 Vikunja 管理员账号 ($VIKUNJA_ADMIN_USER / $EZB_ADMIN_EMAIL) ..."
# 安全说明（#18，审计修复）：不把密码作为命令行参数传给 docker exec，
# 否则会落入宿主机 /proc/<pid>/cmdline（任意本地用户 `ps` 可见）。
# 当前构建的 user create 在缺省 --password 时，会从 TTY 交互式读取两次密码
#（见 vendor/vikunja/pkg/cmd/user.go 的 getPasswordFromFlagOrInput，
# 使用 term.ReadPassword(os.Stdin.Fd())）。故用 -it 分配伪终端，并通过
# bash 内建 printf 把两行相同密码喂入 stdin——密码仅存于本进程内存，
# 不落盘、不进外部进程 argv。set +e 包住以正确捕获 docker 的返回码。
set +e
OUT=$(printf '%s\n%s\n' "$EZB_ADMIN_PASS" "$EZB_ADMIN_PASS" \
  | docker exec -i -t vikunja /app/vikunja/vikunja user create \
      --username "$VIKUNJA_ADMIN_USER" \
      --email "$EZB_ADMIN_EMAIL" 2>&1 \
  | sed 's/\r$//')
RC=${PIPESTATUS[1]}
set -e
if [ $RC -eq 0 ]; then
  echo "  完成（账号 $VIKUNJA_ADMIN_USER 已创建或已存在）。"
elif echo "$OUT" | grep -qiE "already|exist|已存在"; then
  echo "  提示：账号 $VIKUNJA_ADMIN_USER 已存在，可忽略（如需重置请用网页或 CLI）。"
else
  echo "  警告：创建失败（$OUT）。可能容器未就绪或参数错误，请改在网页注册。"
fi

echo "===== 初始化 CLI 步骤完成 ====="
echo "接下来请人工完成（网页）："
echo "  1. Vikunja 设置→API Tokens 新建，填 n8n 变量 vikunja_token"
echo "  2. ezBookkeeping 注册/建账户/建分类/生成 Token，写入 .env 后由 compose 注入 n8n（\$env.EZB_*）"
echo "     （公开注册已由 compose 默认关闭，无需额外 CLI 操作）"
echo "  3. n8n 导入 n8n/*.json 五个工作流"

# ---------- 灾难恢复（非初始化，按需手动执行，见 docs/实施部署手册.md §9.2） ----------
# Vikunja 还原：把备份 zip 放进 data/backup_staging/ 后执行：
#   docker exec -i vikunja /app/vikunja/vikunja restore /backup/<vikunja-xxx.zip>
# ezBookkeeping 还原：停容器 → 用备份 *.db 覆盖 data/ezbookkeeping/data/ 下同名文件 → 起容器
