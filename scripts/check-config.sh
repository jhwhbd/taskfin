#!/usr/bin/env bash
# =============================================================
# 任务财务系统 — 部署前配置自检（可选）
# 作用：
#   1. 检查 .env 关键密钥是否已脱离占位符（避免带着示例值启动）；
#   2. 列出仍需人工保证一致的「同步点」（webhook 密钥等）。
# 用法：bash scripts/check-config.sh [可选 .env 路径，默认 <项目>/.env]
# =============================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="${1:-$PROJECT_DIR/.env}"

echo "===== taskfin 配置自检 ====="
if [ ! -f "$ENV_FILE" ]; then
  echo "未找到 $ENV_FILE（你可能在网页/环境变量中直接配置，跳过校验）。"
  exit 0
fi

bad=0
check() {
  local key="$1" val="$2" hint="$3"
  if [ -z "$val" ] || printf '%s' "$val" | grep -qiE "yourdomain|10001\$|xxxx|replace-with|change-me|example"; then
    echo "  ⚠️  $key 疑似未修改占位符（$hint）"; bad=$((bad+1))
  else
    echo "  ✅ $key 已设置"
  fi
}

_qq=$(grep -E '^QQ_AUTH_CODE=' "$ENV_FILE" | head -1 | cut -d= -f2-)
_ezb=$(grep -E '^EZB_SECRET_KEY=' "$ENV_FILE" | head -1 | cut -d= -f2-)
_wh=$(grep -E '^WEBHOOK_SECRET=' "$ENV_FILE" | head -1 | cut -d= -f2-)
_n8n=$(grep -E '^N8N_ENCRYPTION_KEY=' "$ENV_FILE" | head -1 | cut -d= -f2-)
_domain=$(grep -E '^DOMAIN=' "$ENV_FILE" | head -1 | cut -d= -f2-)
_qqemail=$(grep -E '^QQ_EMAIL=' "$ENV_FILE" | head -1 | cut -d= -f2-)

check "QQ_AUTH_CODE"        "$_qq" "16 位 QQ 授权码"
check "EZB_SECRET_KEY"      "$_ezb" "openssl rand -base64 32 生成的随机密钥"
check "WEBHOOK_SECRET"      "$_wh"  "openssl rand -hex 16 生成的 webhook 密钥"
check "N8N_ENCRYPTION_KEY"  "$_n8n" "openssl rand -base64 32（首次启动前确定并备份）"
check "DOMAIN"              "$_domain" "主域名 yourdomain.com"
check "QQ_EMAIL"            "$_qqemail" "邮箱前缀 10001（非真实账号）"

echo ""
echo "===== .env 格式自检 ====="
# compose 的 dotenv 不剥离「行内 #」，会把注释并进变量值，导致镜像名非法；
# 此处检测行内注释污染（仅整行以 # 开头的注释合法）。
inline_issue=0
while IFS= read -r l; do
  case "$l" in
    \#*|\#) continue ;;                                   # 整行注释，跳过
    *=*'#'*)                                              # 含 = 且行内出现 #
      if printf '%s' "$l" | grep -qE '=[^#]*[[:space:]]*#'; then
        echo "  ⚠️  检测到行内注释（compose 不会剥离，会污染变量值）：$l"
        inline_issue=1
      fi
      ;;
  esac
done < "$ENV_FILE"
[ "$inline_issue" -eq 0 ] && echo "  ✅ 未发现行内注释污染"

echo ""
echo "===== 仍需人工保证一致的同步点 ====="
echo "  1. WEBHOOK_SECRET(.env) 必须与 Vikunja 两个 Webhook 的 Basic Auth 密码一致。"
echo "     三个工作流的 Auth Guard 已优先校验 Authorization: Basic base64(taskfin:<secret>)。"
echo "  2. 当前工作流 Auth Guard 读 \$env.WEBHOOK_SECRET（由 compose 注入），无需 n8n 变量 webhook_secret；旧的 ?secret= 方式仍兼容。"
echo "  3. EBK_SECRET_KEY / N8N_ENCRYPTION_KEY 修改后无法解密旧数据，首次启动前确定并备份。"
echo ""

if [ "$bad" -gt 0 ]; then
  echo "发现 $bad 处疑似占位符未改，请先修改 .env 再部署。"
  exit 1
else
  echo "关键密钥均已设置。请按上方同步点核对后再部署。"
fi
