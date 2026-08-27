#!/usr/bin/env bash
# =============================================================
# 任务财务系统 — 健康检查与告警（宿主机 / 群晖任务计划调用）
# 功能：
#   1. 检查 compose 各容器健康状态（healthcheck）
#   2. 任一核心服务 unhealthy / missing / exited 即推送告警
#   3. 配置的 TASKFIN_ALERT_URL 后，告警 POST 到该地址（与 backup.sh 同一通道）
# 用法：群晖「控制面板 -> 任务计划 -> 用户自定义脚本」每 15 分钟执行
#       bash /path/to/taskfin/scripts/monitor.sh
# 依赖：docker、curl
# =============================================================
set -uo pipefail

# ---------- 配置 ----------
# 项目目录（脚本位于 <项目>/scripts/ 下，自动推导）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR" || exit 1

# 从 .env 读取告警地址（若配置）；未配置则仅打印不推送
if [ -f "$PROJECT_DIR/.env" ]; then
  # 只提取 TASKFIN_ALERT_URL，避免把 .env 全部变量导入 shell
  TASKFIN_ALERT_URL="$(grep -E '^TASKFIN_ALERT_URL=' "$PROJECT_DIR/.env" | tail -1 | cut -d= -f2- | sed 's/^["'\''"]//;s/["'\''"]$//')"
fi
TASKFIN_ALERT_URL="${TASKFIN_ALERT_URL:-}"

# 要监控的核心服务（与 docker-compose.yml 容器名一致）
SERVICES=(npm ddns-go vikunja ezbookkeeping n8n)

# ---------- 告警推送（与 backup.sh 同款） ----------
alert() {
  local msg="$1"
  echo "🚨 $msg" >&2
  if [ -n "$TASKFIN_ALERT_URL" ]; then
    curl -fsS -m 10 -X POST "$TASKFIN_ALERT_URL" \
      -H 'Content-Type: application/json' \
      -d "{\"text\":\"$msg\"}" >/dev/null 2>&1 || echo "  （告警推送失败，忽略）" >&2
  fi
}

# ---------- 检查 ----------
unhealthy=()
for svc in "${SERVICES[@]}"; do
  # 容器是否存在
  if ! docker inspect --format='{{.Id}}' "$svc" >/dev/null 2>&1; then
    unhealthy+=("$svc: 容器不存在")
    continue
  fi
  # 运行状态
  state="$(docker inspect --format='{{.State.Status}}' "$svc" 2>/dev/null)"
  if [ "$state" != "running" ]; then
    unhealthy+=("$svc: 状态=$state（非 running）")
    continue
  fi
  # 健康检查状态（无 healthcheck 的容器该字段为空，视为通过）
  health="$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$svc" 2>/dev/null)"
  if [ "$health" = "unhealthy" ]; then
    unhealthy+=("$svc: 健康检查=unhealthy")
  fi
done

TS="$(date '+%Y-%m-%d %H:%M:%S')"
if [ ${#unhealthy[@]} -eq 0 ]; then
  echo "[$TS] 监控正常：全部 ${#SERVICES[@]} 个服务 healthy/running"
  exit 0
fi

msg="taskfin 健康检查异常 @ $TS：${unhealthy[*]}"
alert "$msg"
# 监控脚本本身退出 0（避免任务计划误报），告警已通过上述通道送达
exit 0
