# 任务 + 财务 自托管系统（taskfin）

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
│   └── backup.sh           # 群晖任务计划用：全量备份 + 高压缩 + 仅留 3 份
├── n8n/                    # n8n 工作流导出（在 n8n 里 Import 即可）
│   ├── vikunja-task-sync.json          # 任务完成 → 记实际支出 → 回写
│   ├── vikunja-budget-plan.json        # 任务新建 → 登计划支出（预算）
│   ├── ezbookkeeping-poll.json         # 财务 → 任务（轮询回贴 + recur 自动勾掉）
│   ├── ezbookkeeping-bill-reminder.json# 账单临期提醒模板（默认禁用，排除贷款）
├── vendor/                 # 上游源码保险副本（详见 vendor/SOURCES.md）
│   ├── SOURCES.md          # 版本/许可证/更新方法
│   ├── vikunja/            # AGPL-3.0（go-vikunja/vikunja 快照，未修改）
│   └── ezbookkeeping/      # MIT（mayswind/ezbookkeeping 快照，未修改）
└── docs/                   # 完整方案文档（设计阶段 v2.7）
    ├── 00-交接总览.md
    ├── 01-需求与决策记录.md
    ├── 02-审查问题与待办.md
    ├── 03-实施部署手册.md   # 可执行部署手册（含 DDNS/NPM/初始化/Webhook/n8n/备份/移动端）
    ├── 04-项目说明（面向使用者）.md
    └── 05-WorkBuddy导入指南.md
```

> ⚠️ 本项目为 **设计阶段完成、尚未实机部署** 的资料。所有结论基于文档调研，`n8n` 工作流 JSON 与部分参数需真机联调。

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
```

启动后：
- NPM 管理后台 `http://<主机IP>:81`（仅内网，勿对公网开放）
- ddns-go `http://<主机IP>:9876`（仅内网）
- 应用通过 `tasks/fin/flow.<你的域名>` 经 HTTPS 访问

详细部署、初始化、Webhook、n8n 配置、备份、移动端与已知风险，见 [`docs/03-实施部署手册.md`](docs/03-实施部署手册.md) 与 [`docs/02-审查问题与待办.md`](docs/02-审查问题与待办.md)。

## 已知最高风险（部署前必读）

1. **CalDAV 手机闹钟**：Vikunja 的 CalDAV 可能只同步事件、不导出 VALARM，手机可能不弹闹钟；可靠提醒仍是 QQ 邮件兜底。
2. **n8n 四个 JSON 未实机校验**：`fund:` 标签解析、金额×100、`typeVersion`、Webhook 路径需在真机联调。
3. **`/share/backup` 真实路径**：群晖共享多挂在 `/volume1/share/backup`，`scripts/backup.sh` 里的 `SMB_DIR` 需按真实路径改。

## 镜像版本锁定

`docker-compose.yml` 中所有镜像均使用**具体版本号**（非 `latest`），以保证每次启动拉到的镜像一致、出问题时可定位。版本在文件顶部以变量集中声明：

| 服务 | 镜像 | 当前锁定版本 |
|---|---|---|
| Nginx Proxy Manager | jc21/nginx-proxy-manager | v2.15.1 |
| ddns-go | jeessy/ddns-go | v6.17.5 |
| Vikunja | vikunja/vikunja | v2.5.0 |
| ezBookkeeping | mayswind/ezbookkeeping | v1.6.1 |
| n8n | n8nio/n8n | 1.123.72 |

> ⚠️ n8n 的 Docker tag **不带 v 前缀**（`1.123.72` 而非 `v1.123.72`），与其余服务不同，注意区分。

**升级方法**：编辑 `docker-compose.yml` 顶部对应版本变量 → `docker compose pull` → `docker compose up -d`。升级前建议查看上游 CHANGELOG，确认兼容性。

## 上游源码版本校验

仓库自带 `scripts/check-vendor.sh`，可在群晖 SSH 中运行，比对 `vendor/` 中收录的上游源码哈希与 GitHub 最新提交是否一致，便于判断何时需要更新 vendor 快照：

```bash
bash scripts/check-vendor.sh
```

## 第三方源码与许可证

本项目在 `vendor/` 下收录了所依赖的上游开源项目**完整源码快照**（保险副本，非日常运行依赖），以便在官方仓库/镜像不可用时仍可自包含构建。详细说明与更新方法见 [`vendor/SOURCES.md`](vendor/SOURCES.md)：

| 项目 | 上游 | 许可证 | 在本项目中的角色 |
|---|---|---|---|
| Vikunja | go-vikunja/vikunja | **AGPL-3.0** | 任务管理（日常用官方镜像；源码为保险副本） |
| ezBookkeeping | mayswind/ezbookkeeping | **MIT** | 财务管理（同上） |

> ⚠️ **AGPL-3.0 义务提示**：Vikunja 是强 copyleft 许可证。若你**修改其源码**并**通过网络交互方式向他人提供该服务**（例如自托管并允许家庭成员/其他用户访问），须按 AGPL 第 13 条向这些用户提供修改后的对应源码。本项目当前为未修改快照，纯自用一般不触发该义务。

## License

本项目自身代码以 [MIT](LICENSE) 授权；`vendor/` 内各项目的许可证以其自带的 `LICENSE` 文件为准（Vikunja: AGPL-3.0 / ezBookkeeping: MIT）。
