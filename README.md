# 任务 + 财务 自托管系统（taskfin）

## 🌐 English Summary

**taskfin** is a self-hosted, all-local stack for **task management + personal finance + automation**, designed to run on a Synology NAS (or any Docker host). Your data never leaves your network and depends on no third-party cloud.

**Components**
- **Vikunja** — task management (categories → projects → tasks, due/overdue email reminders, mobile PWA + CalDAV).
- **ezBookkeeping** — personal finance (income/expense/balance, reports, recurring transactions, official mobile app).
- **n8n** — automation bridge syncing tasks ↔ finance (create task → log budget; complete task → record actual spend; finance charge → write back to task).
- **Nginx Proxy Manager** + **ddns-go** — HTTPS reverse proxy and dynamic DNS (Namecheap).

**Architecture** — All three apps run inside the internal Docker network and talk to each other without leaving the LAN. Only ports **80/443** are exposed to the public internet (via NPM). Data is stored in **SQLite**; an automated `backup.sh` performs full backups with high compression and keeps only the 3 latest copies.

**Deploy** — `docker compose up -d` driven by environment variables (copy `.env.example` → `.env`). See [`docs/实施部署手册.md`](docs/实施部署手册.md) for the full step-by-step guide (Chinese). Upstream source is vendored under `vendor/` (Vikunja: AGPL-3.0, ezBookkeeping: MIT) and **rebranded to TaskFIN** (app name, icons, PWA splash screens) — the Vikunja & ezBookkeeping images are **built from this modified source** (not pulled from upstream registries). See [`vendor/SOURCES.md`](vendor/SOURCES.md).

> ⚠️ This repo is **design-complete but not yet deployed to real hardware**; the n8n workflows and some parameters need live testing.

---

在群晖（或任意 Docker 主机）上自托管一套 **任务管理 + 财务管理 + 自动化桥接** 系统，数据完全自己掌握、不依赖任何第三方云服务。

- **任务管理** — [Vikunja](https://vikunja.io/)：类别 → 项目 → 任务三层结构，起止时间、里程碑、到期/临期邮件提醒、移动端 PWA + CalDAV。
- **财务管理** — [ezBookkeeping](https://ezbookkeeping.mayswind.net/)：支出/收入/结余、统计报表、周期交易自动过账、官方手机 App。
- **自动化桥接** — [n8n](https://n8n.io/)：任务↔财务双向同步（建任务登预算、完成任务记实际支出、财务扣款回写任务）。
- **接入层** — Nginx Proxy Manager（HTTPS + 反代）+ ddns-go（Namecheap 动态 DNS）。

三套应用只跑在 Docker 内网，互相通信不经公网；外网仅放行 80/443。

## 架构

```
   电脑 / 手机 ──HTTPS──▶ NPM 反代 ──▶ tasks.<域名> → Vikunja
                                     ├──▶ fin.<域名>  → ezBookkeeping
                                     └──▶ flow.<域名> → n8n

   Vikunja ──Webhook──▶ n8n ──API──▶ ezBookkeeping   （任务→财务）
   ezBookkeeping ──轮询──▶ n8n ──API──▶ Vikunja       （财务→任务）
   全部走内网，不经公网
```

技术栈：Vikunja + ezBookkeeping + n8n + Nginx Proxy Manager + ddns-go，均为 Docker 容器，数据库用 SQLite。

## 目录结构

```
taskfin/
├── docker-compose.yml      # 核心编排（环境变量驱动，密钥走 .env）
├── .env.example            # 环境变量样例（复制为 .env 后填真实值）
├── .gitignore
├── README.md
├── LICENSE
├── scripts/
│   ├── backup.sh           # 群晖任务计划用：全量备份 + 高压缩 + 仅留 3 份
│   ├── init.sh             # 部署后初始化：Vikunja 建首管理员（幂等可重跑）
│   └── check-vendor.sh     # 比对 vendor/ 上游源码哈希与 GitHub 最新提交
├── n8n/                    # n8n 工作流导出（在 n8n 里 Import from File 导入；默认均禁用，按需启用）
│   ├── vikunja-task-sync.json          # 任务完成 → 记实际支出 → 回写
│   ├── vikunja-budget-plan.json        # 任务新建 → 留「预算」评论（不记真实支出）
│   ├── ezbookkeeping-poll.json         # 财务 → 任务（轮询回贴 + recur 自动勾掉）
│   ├── ezbookkeeping-bill-reminder.json# 账单临期提醒模板（默认禁用，排除贷款）
│   └── ezbookkeeping-recur-tag.json    # 周期交易自动打标（每日06:30+手动；默认禁用）
├── vendor/                 # 上游源码（已做品牌化改造，详见 vendor/SOURCES.md）
│   ├── SOURCES.md          # 版本/许可证/更新方法
│   ├── vikunja/            # AGPL-3.0（go-vikunja/vikunja 快照，已做品牌化改造）
│   └── ezbookkeeping/      # MIT（mayswind/ezbookkeeping 快照，已做品牌化改造）
└── docs/                   # 项目文档（4 份）
    ├── 实施部署手册.md          # 可照做的部署步骤（DDNS/NPM/初始化/Webhook/n8n/备份/移动端 + 已知风险）
    ├── 项目介绍说明.md          # 项目定位、功能、架构、设计决策与当前状态
    ├── NAS构建与回滚.md         # NAS 实机构建前置检查、构建步骤与回滚方案
    └── n8n变量清单.md           # n8n 变量速查（6 个 $vars.* 取值位置与 .env 映射）
```

> ⚠️ 本项目为 **设计阶段完成、尚未实机部署** 的资料。所有结论基于文档调研，`n8n` 工作流 JSON 与部分参数需真机联调。

> 🎨 **品牌化（Rebranding）**：本项目的 Vikunja 与 ezBookkeeping 源码已统一改造为 **TaskFIN** 品牌——应用名（含全部界面语言与后端邮件署名）、favicon、PWA 图标、iOS 启动图、logo 均已替换；保留上游 "Powered by" 与 GitHub 链接作开源合规署名。两份组件镜像**从 `vendor/` 里的修改后源码构建**（见下方「镜像版本锁定」与部署手册 §2），而非拉取上游官方镜像。品牌素材源在 `branding/`，生成脚本为 `scripts/gen-icons.cjs` 与 `scripts/gen-splash.cjs`；**重跑这两个脚本前需先 `npm install`**（仓库根 `package.json` 已声明 `opentype.js` / `@resvg/resvg-js` / `png-to-ico` 依赖，见 P8）。

## 快速开始

```bash
git clone <your-repo-url> taskfin && cd taskfin

# 1. 准备环境变量
cp .env.example .env
#   编辑 .env，填好 DOMAIN / QQ_EMAIL / QQ_AUTH_CODE / EZB_SECRET_KEY

# 2. 建运行时数据目录
mkdir -p data/npm/data data/npm/letsencrypt data/ddns-go \
         data/vikunja/files data/vikunja/db \
         data/ezbookkeeping/data data/ezbookkeeping/storage \
         data/n8n data/backup_staging
chown -R 1000:1000 data/ezbookkeeping/data data/ezbookkeeping/storage

# 3. 启动
docker compose up -d

# 4. 导入 n8n 工作流（默认均禁用 active:false，按需手动 Enable）
#   在 n8n 界面（flow.<域名> → Workflows → Import from File）逐个导入 n8n/*.json
#   必开：vikunja-task-sync / vikunja-budget-plan / ezbookkeeping-poll
#   选开：ezbookkeeping-bill-reminder（仅过滤、未接发送节点）、ezbookkeeping-recur-tag（每日06:30自动 + 手动 POST /recur-tag?secret=<webhook_secret>）
#   另：ezBookkeeping 需在配置中开启 enable_scheduled_transaction=true（默认 false），否则周期交易无法建立、recur 闭环不工作
```

启动后：
- NPM 管理后台 `http://<主机IP>:81`（仅内网，勿对公网开放）
- ddns-go `http://<主机IP>:9876`（仅内网）
- 应用通过 `tasks/fin/flow.<你的域名>` 经 HTTPS 访问

详细部署、初始化、Webhook、n8n 配置、备份、移动端与已知风险，见 [`docs/实施部署手册.md`](docs/实施部署手册.md)；项目定位、功能、架构、设计决策与当前状态见 [`docs/项目介绍说明.md`](docs/项目介绍说明.md)。

## 已知最高风险（部署前必读）

1. **CalDAV 手机闹钟**：Vikunja 的 CalDAV 可能只同步事件、不导出 VALARM，手机可能不弹闹钟；可靠提醒仍是 QQ 邮件兜底。
2. **n8n 五个 JSON 未实机校验**：`fund:` 标签解析、金额×100、`typeVersion`、Webhook 路径需在真机联调。
3. **确认备份共享子目录真实存在**：`scripts/backup.sh` 的 `SMB_DIR` 已锚定 `/volume1/share/taskfin_backup`，部署前请在 DSM「控制面板 → 共享文件夹」确认该子目录真实存在（否则脚本会因目录不存在而报错退出）。
4. **n8n 共 5 个工作流**：核心 3 个（task-sync / budget-plan / poll）必开；`recur-tag` 默认禁用、每日 06:30 定时 + 手动 `POST /recur-tag?secret=<webhook_secret>` 触发（仅当使用「定期扣款」闭环时才需启用）；`bill-reminder` 默认禁用且当前模板未接发送节点、启用也不发邮件。所有流程的 webhook 密钥 `webhook_secret` 须与 §5.3 的 `WEBHOOK_SECRET` 及 Vikunja Webhook URL 里的 `?secret=` 保持一致。

## 镜像版本锁定

`docker-compose.yml` 中所有镜像均使用**具体版本号**（非 `latest`），以保证每次启动拉到的镜像一致、出问题时可定位。版本在 `.env.example` 中以变量集中声明，compose 通过 `${XXX_VERSION}` 引用（复制 `.env.example` 为 `.env` 后生效）：

| 服务 | 镜像 | 当前锁定版本 |
|---|---|---|
| Nginx Proxy Manager | jc21/nginx-proxy-manager | v2.15.1 |
| ddns-go | jeessy/ddns-go | v6.17.5 |
| Vikunja | vikunja/vikunja | v2.5.0 | 从 `vendor/` 源码构建（版本仅记录，compose 不再拉此镜像） |
| ezBookkeeping | mayswind/ezbookkeeping | v1.6.1 | 从 `vendor/` 源码构建（版本仅记录，compose 不再拉此镜像） |
| n8n | n8nio/n8n | 1.123.72 |

> ⚠️ n8n 的 Docker tag **不带 v 前缀**（`1.123.72` 而非 `v1.123.72`），与其余服务不同，注意区分。

**升级方法**：编辑 `.env.example` 中对应 `*_VERSION` 变量（保存后 `cp .env.example .env` 或把改动合并进现有 `.env`）→ `docker compose pull` → `docker compose up -d`。升级前建议查看上游 CHANGELOG，确认兼容性。

## 上游源码版本校验

仓库自带 `scripts/check-vendor.sh`，可在群晖 SSH 中运行，比对 `vendor/` 中收录的上游源码哈希与 GitHub 最新提交是否一致，便于判断何时需要更新 vendor 快照：

```bash
bash scripts/check-vendor.sh
```

## 第三方源码与许可证

本项目在 `vendor/` 下收录了所依赖的上游开源项目**完整源码快照**（保险副本，非日常运行依赖），以便在官方仓库/镜像不可用时仍可自包含构建。详细说明与更新方法见 [`vendor/SOURCES.md`](vendor/SOURCES.md)：

| 项目 | 上游 | 许可证 | 在本项目中的角色 |
|---|---|---|---|
| Vikunja | go-vikunja/vikunja | **AGPL-3.0** | 任务管理（从 vendored 源码构建品牌化镜像，UI 显示 TaskFIN） |
| ezBookkeeping | mayswind/ezbookkeeping | **MIT** | 财务管理（同上） |

> ⚠️ **AGPL-3.0 义务提示**：Vikunja 是强 copyleft 许可证。本项目**已修改 Vikunja 源码**（品牌化：应用名、图标、PWA 启动图统一改为 TaskFIN，并经 `docker-compose.yml` 从源码构建镜像）。若你**通过网络交互方式向他人（如家庭成员）提供该服务**，须按 AGPL 第 13 条向这些用户提供修改后的对应源码——**本仓库（含 `vendor/vikunja/` 的修改后源码）即满足该义务**，部署时保留仓库可访问即可。纯单机自用一般不触发该义务。

## License

本项目自身代码以 [MIT](LICENSE) 授权；`vendor/` 内各项目的许可证以其自带的 `LICENSE` 文件为准（Vikunja: AGPL-3.0 / ezBookkeeping: MIT）。
