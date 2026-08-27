# n8n 变量清单（首次部署速查）

本文件汇总 `n8n/` 下 5 个工作流在 n8n `Settings → Variables` 中需要填写的变量，以及它们与本仓库 `.env` 的对应关系。导入工作流后、启用前务必逐项填好，否则流程会因取不到变量而失败。

## 一、n8n `$vars.*` 变量

| n8n 变量名 | 配置位置 | 取值 | 用途 | 使用的工作流 |
|---|---|---|---|---|
| `ezb_token` | n8n `Settings → Variables` | ezBookkeeping 用户的 API Token（网页「设置 → 令牌」生成） | `Authorization: Bearer` 调用 ezB API | task-sync / poll / recur-tag / bill-reminder |
| `vikunja_token` | n8n `Settings → Variables` | Vikunja 用户的 API Token（网页「设置 → 令牌」生成） | `Authorization: Bearer` 调用 Vikunja API | task-sync / budget-plan |
| `ezb_cat_expense` | n8n `Settings → Variables` | ezB 支出分类 ID（**字符串**，如 `"1"`） | task-sync 建账时填 `categoryId`（见下方注意） | task-sync |
| `ezb_account_cash_id` | n8n `Settings → Variables` | ezB 现金账户 ID（**字符串**） | `fund:...:cash` 任务记账的目标账户 `sourceAccountId` | task-sync |
| `ezb_account_deposit_id` | n8n `Settings → Variables` | ezB 存款账户 ID（**字符串**） | `fund:...:deposit` 任务记账的目标账户 `sourceAccountId` | task-sync |
| `ezb_cat_loan` | n8n `Settings → Variables` | ezB 贷款还款分类 ID（**字符串**，如 `"3"`） | `ezbookkeeping-bill-reminder` 引用 `{{ $vars.ezb_cat_loan }}` 识别「贷款还款」分类 | bill-reminder |

> ⚠️ **ID 字段必须按字符串发送**：ezB 源码中 `categoryId`、`sourceAccountId` 绑定为 `,string`（`json:"categoryId,string"`）。在 n8n 变量里填数字会被当成 JSON number 导致绑定失败（400）。务必填带引号的字符串（如 `"1"`）；当前流程用 `={{ $vars.xxx }}` 表达式，n8n 通常会以字符串发送，但若在变量 UI 里直接填了纯数字仍可能踩坑——请填字符串形式。

## 二、与 `.env` 的映射

| 概念 | `.env` 项 | 说明 |
|---|---|---|
| Webhook 密钥 | `WEBHOOK_SECRET` | 已**单源化**：`.env` 的 `WEBHOOK_SECRET` 由 `docker-compose.yml` 注入 n8n 容器环境变量，三个工作流的 Auth Guard 直接读 `$env.WEBHOOK_SECRET`（即 `process.env.WEBHOOK_SECRET`）校验 `Authorization: Basic` 头——**无需在 n8n 新建 `webhook_secret` 变量**。改 `.env` 后 `docker compose restart n8n` 即生效。Vikunja 侧只需保证 Webhook 的 Basic Auth 密码（或 URL 末尾 `?secret=`）与此值一致（见 `docs/实施部署手册.md` §6）。 |
| ezB 用户令牌 | （无独立 `.env` 项） | ezB API Token 直接在 n8n `ezb_token` 填，不从 `.env` 读取。 |
| Vikunja 用户令牌 | （无独立 `.env` 项） | 同上，填 n8n `vikunja_token`。 |

> 注：`.env` 中的 `EZB_SECRET_KEY` 是 ezB 的**数据加密密钥**（用于加密数据库中的敏感字段），与这里的 API Token（`ezb_token`）**不是一回事**，请勿混淆。

## 三、填写顺序建议

1. 在 ezB / Vikunja 网页各生成一个 API Token。
2. n8n `Settings → Variables` 新建上述 6 个变量，粘贴对应值（ID 类按字符串填）。
3. 在 `.env` 设置 `WEBHOOK_SECRET`（compose 会自动注入 n8n，Auth Guard 直接读取，无需在 n8n 建 `webhook_secret` 变量）；并确认 Vikunja 两个 Webhook 的 Basic Auth 密码（或 URL 末尾 `?secret=`）与此值一致。
4. 导入 5 个 `n8n/*.json`，按需要 Enable（核心 3 个必开；recur-tag / bill-reminder 按需）。
5. 逐步联调（见手册 §B2）：先手动「执行工作流」跑通，再启用 Webhook / 定时。

## 四、ezB 周期交易前置开关

使用「定期扣款」闭环（`recur-tag` + `poll` 回写）前，必须开启 ezB 的周期交易功能：

- 配置项：`enable_scheduled_transaction`（位于 `[user]` 段）。**正确环境变量名：`EBK_USER_ENABLE_SCHEDULED_TRANSACTION`**（拼接规则 `EBK_<段>_<键>`；旧文档曾误作 `EBK_SCHEDULED_TRANSACTION_ENABLED`）。本仓库 vendored 快照的 `conf/ezbookkeeping.ini` 已默认 `true`、镜像 `Dockerfile` 铺入 conf，故默认已开启；`docker-compose.yml` 也已显式声明 `EBK_USER_ENABLE_SCHEDULED_TRANSACTION=true` 以不依赖 ini 默认值。
- 未开启则周期交易无法建立、不会自动过账，整个 recur 闭环不工作。
