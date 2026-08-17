#!/usr/bin/env bash
# =============================================================
# 任务财务系统 — 自动备份脚本（宿主机 / 群晖任务计划调用）
# 功能：
#   1. Vikunja 全量导出 (vikunja dump -> ZIP，含 DB+附件，可 restore 完整还原)
#   2. ezBookkeeping 数据库文件拷贝 (SQLite，挂回即恢复)
#   3. ezBookkeeping 人读 CSV 导出 (可选，辅助查看)
#   4. 高压缩：7z -mx=9 > tar.xz(-9) > tar.gz 自动降级
#   5. 写入群晖 Windows 共享文件夹 taskfin_backup
#   6. 仅保留最近 3 份
# 用法：群晖「控制面板 -> 任务计划 -> 用户自定义脚本」每周日 03:00 执行
#       bash /volume1/docker/taskfin/scripts/backup.sh
# =============================================================
set -euo pipefail

# ---------- 可配置区（按你环境修改） ----------
PROJECT_DIR="/volume1/docker/taskfin"          # compose 项目目录
STAGING="$PROJECT_DIR/backup_staging"          # 临时落盘目录（已挂进 vikunja 容器 /backup）
# 备份写入目标：本机群晖共享文件夹 /share/backup（Windows 侧 \\<群晖内网IP>\share\backup）
# 说明：DSM 的共享文件夹实际挂载路径通常为 /volume1/share/backup；若你的 share 名不是 share，
#       或共享挂在别的 volume（如 /volume2），请把下面路径改成真实绝对路径。
SMB_DIR="/share/backup"
# 若要备份到别的机器的 Windows 共享：先群晖「文件服务 -> 挂载 CIFS」挂好，
# 再把下面这行改成挂载点路径，例如 /volume1/@mount/CIFS/remote_backup
# SMB_DIR="/volume1/@mount/CIFS/remote_backup"

# ezBookkeeping CSV 导出（人读辅助，可选）。需 API Token。
EXPORT_CSV=1
EZB_TOKEN=""                                   # 填你的 ezB API Token（在 n8n 变量 ezb_token 同值）
# Vikunja dump 不需要 Token（走容器内部命令）

LOG_FILE="$PROJECT_DIR/backup_staging/backup.log"
TS="$(date +%Y%m%d-%H%M%S)"
# ------------------------------------------------------------

mkdir -p "$STAGING" "$SMB_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "===== 备份开始 $TS ====="

# 1) Vikunja 全量 dump -> 容器内 /backup -> 宿主机 STAGING
echo "[1/4] Vikunja dump ..."
docker exec vikunja sh -c "cd /backup && /app/vikunja/vikunja dump" \
  || { echo "Vikunja dump 失败，退出"; exit 1; }

# 2) ezBookkeeping 数据库文件
echo "[2/4] 拷贝 ezBookkeeping 数据库 ..."
cp -f "$PROJECT_DIR"/ezbookkeeping/data/*.db "$STAGING"/ 2>/dev/null \
  || echo "  警告：未找到 ezB db 文件，跳过"

# 3) ezBookkeeping 人读 CSV（可选）
if [ "$EXPORT_CSV" = "1" ] && [ -n "$EZB_TOKEN" ]; then
  echo "[3/4] 导出 ezBookkeeping CSV（人读辅助）..."
  docker exec ezbookkeeping sh -c "wget -qO- 'http://localhost:8080/api/data/export.csv?utcOffset=480' --header='Authorization: Bearer $EZB_TOKEN'" \
    > "$STAGING/ezbookkeeping.csv" 2>/dev/null \
    || echo "  警告：CSV 导出失败，继续（不影响主备）"
else
  echo "[3/4] 跳过 CSV 导出（EXPORT_CSV=0 或未填 EZB_TOKEN）"
fi

# 4) 高压缩 + 写入共享 + 仅留 3 份
echo "[4/4] 压缩并写入共享 ..."
FILES=( "$STAGING"/vikunja-*.zip "$STAGING"/*.db "$STAGING"/ezbookkeeping.csv )
# 去掉不存在的项
existing=()
for f in "${FILES[@]}"; do [ -e "$f" ] && existing+=("$f"); done
if [ ${#existing[@]} -eq 0 ]; then
  echo "没有可备份的文件，退出"; exit 1
fi

if command -v 7z >/dev/null 2>&1; then
  ARCHIVE="$SMB_DIR/taskfin-backup-$TS.7z"
  echo "  使用 7z -mx=9 (LZMA2 最高压缩率)"
  7z a -t7z -mx=9 -mmt=2 "$ARCHIVE" "${existing[@]}"
elif command -v xz >/dev/null 2>&1; then
  ARCHIVE="$SMB_DIR/taskfin-backup-$TS.tar.xz"
  echo "  7z 不可用，回退 tar.xz (-9)"
  tar -cJf "$ARCHIVE" -C "$STAGING" $(ls -1 "$STAGING" | grep -E 'vikunja-.*\.zip|\.db$|ezbookkeeping\.csv')
else
  ARCHIVE="$SMB_DIR/taskfin-backup-$TS.tgz"
  echo "  7z/xz 均不可用，回退 tar.gz"
  tar -czf "$ARCHIVE" -C "$STAGING" $(ls -1 "$STAGING" | grep -E 'vikunja-.*\.zip|\.db$|ezbookkeeping\.csv')
fi
echo "  已生成: $ARCHIVE ($(du -h "$ARCHIVE" | cut -f1))"

# 仅保留最近 3 份
echo "  清理旧备份，仅留最近 3 份 ..."
ls -t "$SMB_DIR"/taskfin-backup-*.* | tail -n +4 | xargs -r rm -f
echo "  当前共享内备份："
ls -lh "$SMB_DIR"/taskfin-backup-*.* 2>/dev/null | awk '{print $5, $9}'

# 清理本次临时文件
rm -f "$STAGING"/vikunja-*.zip "$STAGING"/*.db "$STAGING"/ezbookkeeping.csv 2>/dev/null || true

echo "===== 备份完成 $(date +%Y%m%d-%H%M%S) ====="
