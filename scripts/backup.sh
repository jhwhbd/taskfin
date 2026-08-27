#!/usr/bin/env bash
# =============================================================
# 任务财务系统 — 自动备份脚本（宿主机 / 群晖任务计划调用）
# 功能：
#   1. Vikunja 全量导出 (vikunja dump -> ZIP，含 DB+附件，可 restore 完整还原)
#   2. ezBookkeeping 数据库文件拷贝 (SQLite，挂回即恢复)
#   3. ezBookkeeping 人读 CSV 导出 (可选，辅助查看)
#   4. 高压缩：7z -mx=9 > tar.xz(-9) > tar.gz 自动降级
#   5. 写入群晖 Windows 共享文件夹 taskfin_backup
#   6. 按 GFS 思路保留近期多份（KEEP_DAILY，默认 14）
# 用法：群晖「控制面板 -> 任务计划 -> 用户自定义脚本」每周日 03:00 执行
#       bash /path/to/taskfin/scripts/backup.sh   # 路径按脚本实际位置自动推导，无需硬编码
# =============================================================
set -euo pipefail

# ---------- 可配置区（按你环境修改） ----------
# PROJECT_DIR 由脚本位置自动推导（脚本位于 <项目>/scripts/ 下），部署路径变更无需改这里。
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"     # compose 项目目录（自动推导）
STAGING="$PROJECT_DIR/data/backup_staging"     # 临时落盘目录（已挂进 vikunja 容器 /backup；注意：与 compose 卷 ./data/backup_staging 对应，含 data/ 前缀）
# 备份写入目标：本机群晖共享文件夹的真实绝对路径。
# 群晖共享文件夹在文件系统内的真实路径为 /volume1/<共享名>/<子目录>，
# 请先在 DSM「控制面板 -> 共享文件夹」建好子目录（如 share/taskfin_backup），再把下面改成真实路径。
# 注意：不要用旧版 DSM 的 /share/<名> 软链接别名，新版可能不存在，会静默写错位置。
SMB_DIR="${TASKFIN_BACKUP_DIR:-/volume1/share/taskfin_backup}"
# 每种格式保留份数（GFS 思路：财务数据不宜只留 3 份；按日频≈保留 N 天）。可用 TASKFIN_KEEP_DAILY 覆盖。
KEEP_DAILY="${TASKFIN_KEEP_DAILY:-14}"
# 若要备份到别的机器的 Windows 共享：先群晖「文件服务 -> 挂载 CIFS」挂好，
# 再把下面这行改成挂载点路径，例如 /volume1/@mount/CIFS/remote_backup
# SMB_DIR="/volume1/@mount/CIFS/remote_backup"

# ezBookkeeping CSV 导出（人读辅助，可选）。需 API Token。
EXPORT_CSV=1
EZB_TOKEN=""                                   # 填你的 ezB API Token（在 n8n 变量 ezb_token 同值）
# Vikunja dump 不需要 Token（走容器内部命令）

LOG_FILE="$STAGING/backup.log"
TS="$(date +%Y%m%d-%H%M%S)"
# ------------------------------------------------------------

# 目标共享目录必须预先存在（不自动创建，避免静默写错位置导致备份丢失）
if [ ! -d "$SMB_DIR" ]; then
  echo "错误：备份目标目录不存在：$SMB_DIR" >&2
  echo "请先在 DSM 建好该共享子目录，或修改脚本顶部 SMB_DIR 为真实路径。" >&2
  exit 1
fi
mkdir -p "$STAGING"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "===== 备份开始 $TS ====="

# 1) Vikunja 全量 dump -> 容器内 /backup -> 宿主机 STAGING
echo "[1/4] Vikunja dump ..."
docker exec vikunja sh -c "/app/vikunja/vikunja dump --path /backup" \
  || { echo "Vikunja dump 失败，退出"; exit 1; }

# 2) ezBookkeeping 数据库文件
# P4：ezB 默认用 WAL 模式，仅拷主库 *.db 会遗漏 -wal/-shm，且拷贝瞬间若有写入可能不一致。
# 这里同时拷 db + -wal + -shm，保证快照一致（WAL 文件可能与主库同名前缀，不存在则跳过）。
echo "[2/4] 拷贝 ezBookkeeping 数据库（含 WAL） ..."
EZB_DATA="$PROJECT_DIR/data/ezbookkeeping/data"
copied=0
for f in ezbookkeeping.db ezbookkeeping.db-wal ezbookkeeping.db-shm; do
  if [ -f "$EZB_DATA/$f" ]; then
    cp -f "$EZB_DATA/$f" "$STAGING"/ && copied=$((copied+1))
  fi
done
[ "$copied" -gt 0 ] || echo "  警告：未找到 ezB db 文件，跳过"

# P10：备份完整性自检 —— 用 sqlite3 对拷贝出的 ezB 主库做 integrity_check；
# 失败仅告警不阻断（主备仍生成），但提示"备份可能不可恢复"。
if command -v sqlite3 >/dev/null 2>&1; then
  if [ -f "$STAGING/ezbookkeeping.db" ]; then
    if sqlite3 "$STAGING/ezbookkeeping.db" "PRAGMA integrity_check;" | grep -q '^ok$'; then
      echo "  ezB 数据库完整性检查通过 (integrity_check=ok)"
    else
      echo "  ⚠️ 警告：ezBookkeeping 数据库完整性检查未通过，备份可能损坏！" >&2
    fi
  fi
else
  echo "  （未安装 sqlite3，跳过 ezB 数据库完整性自检；建议宿主机安装 sqlite3 以便校验）"
fi

# 3) ezBookkeeping 人读 CSV（可选）
# P9：ezB 镜像未必自带 wget；优先 wget，缺失则回退 curl（均走容器内访问，因 ezB 未映射主机端口）。
# 前置条件：ezB 需开启 EBK_DATA_ENABLE_EXPORT=true 且 EZB_TOKEN 已填，否则该步自动跳过。
if [ "$EXPORT_CSV" = "1" ] && [ -n "$EZB_TOKEN" ]; then
  echo "[3/4] 导出 ezBookkeeping CSV（人读辅助）..."
  docker exec ezbookkeeping sh -c "(command -v wget >/dev/null 2>&1 && wget -qO- 'http://localhost:8080/api/v1/data/export.csv' --header='Authorization: Bearer $EZB_TOKEN' --header='X-Timezone-Name: Asia/Shanghai') || (command -v curl >/dev/null 2>&1 && curl -s -H 'Authorization: Bearer $EZB_TOKEN' -H 'X-Timezone-Name: Asia/Shanghai' 'http://localhost:8080/api/v1/data/export.csv')" \
    > "$STAGING/ezbookkeeping.csv" 2>/dev/null \
    || echo "  警告：CSV 导出失败（可能未开 EBK_DATA_ENABLE_EXPORT 或容器内无 wget/curl），继续（不影响主备）"
else
  echo "[3/4] 跳过 CSV 导出（EXPORT_CSV=0 或未填 EZB_TOKEN）"
fi

# 4) 高压缩 + 写入共享 + 按 KEEP_DAILY 留存
echo "[4/4] 压缩并写入共享 ..."
# P1-2：WAL 三件套一并归档（仅 *.db 会漏掉 -wal/-shm，导致未 checkpoint 时丢最近交易）
FILES=( "$STAGING"/vikunja-*.zip "$STAGING"/*.db "$STAGING"/*.db-wal "$STAGING"/*.db-shm "$STAGING"/ezbookkeeping.csv )
# 去掉不存在的项；同时取出文件名（供 tar -C 使用，避免 ls 命令替换对含空格文件名分词出错）
existing=()
for f in "${FILES[@]}"; do [ -e "$f" ] && existing+=("$f"); done
if [ ${#existing[@]} -eq 0 ]; then
  echo "没有可备份的文件，退出"; exit 1
fi
names=()
for f in "${existing[@]}"; do names+=("$(basename "$f")"); done

if command -v 7z >/dev/null 2>&1; then
  ARCHIVE="$SMB_DIR/taskfin-backup-$TS.7z"
  echo "  使用 7z -mx=9 (LZMA2 最高压缩率)"
  # P5：进入 STAGING 后用相对文件名打包，包内结构与 tar 分支一致（仅文件名，不含 $STAGING/ 层级）
  ( cd "$STAGING" && 7z a -t7z -mx=9 -mmt=2 "$ARCHIVE" "${names[@]}" )
elif command -v xz >/dev/null 2>&1; then
  ARCHIVE="$SMB_DIR/taskfin-backup-$TS.tar.xz"
  echo "  7z 不可用，回退 tar.xz (-9)"
  tar -cJf "$ARCHIVE" -C "$STAGING" "${names[@]}"
else
  ARCHIVE="$SMB_DIR/taskfin-backup-$TS.tgz"
  echo "  7z/xz 均不可用，回退 tar.gz"
  tar -czf "$ARCHIVE" -C "$STAGING" "${names[@]}"
fi
echo "  已生成: $ARCHIVE ($(du -h "$ARCHIVE" | cut -f1))"

# 按 KEEP_DAILY 保留（GFS 思路；用 while 读行而非 ls|xargs 分词，文件名安全）
echo "  清理旧备份，每种格式仅留最近 ${KEEP_DAILY} 份 ..."
for ext in 7z tar.xz tgz; do
  ls -t "$SMB_DIR"/taskfin-backup-*."$ext" 2>/dev/null | tail -n +$((KEEP_DAILY+1)) | while IFS= read -r f; do
    rm -f "$f"
  done
done
echo "  当前共享内备份："
ls -lh "$SMB_DIR"/taskfin-backup-*.* 2>/dev/null | awk '{print $5, $9}'

# 清理本次临时文件
rm -f "$STAGING"/vikunja-*.zip "$STAGING"/*.db "$STAGING"/*.db-wal "$STAGING"/*.db-shm "$STAGING"/ezbookkeeping.csv 2>/dev/null || true

echo "===== 备份完成 $(date +%Y%m%d-%H%M%S) ====="
