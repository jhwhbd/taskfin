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
│   ├── backup-csv-7z-email.json        # 弃用占位，勿用
│   └── Dockerfile                      # 备用（当前 compose 用官方镜像）
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

## License

[MIT](LICENSE)
