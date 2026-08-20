# n8n 变量清单（首次部署速查）

本文件汇总 `n8n/` 下 5 个工作流在 n8n `Settings → Variables` 中需要填写的变量，以及它们与本仓库 `.env` 的对应关系。导入工作流后、启用前务必逐项填好，否则流程会因取不到变量而失败。

## 一、n8n `$vars.*` 变量

| n8n 变量名 | 配置位置 | 取值 | 用途 | 使用的工作流 |
|---|---|---|---|---|
| `webhook_secret` | n8n `Settings → Variables` | 随机串（建议 `openssl rand -base64 24`） | P1 静态密钥校验：Webhook 节点比对 `?secret=`，不符直接丢弃 | task-sync / budget-plan / recur-tag |
| `ezb_token` | n8n `Settings → Variables` | ezBookkeeping 用户的 API Token（网页「设置 → 令牌」生成） | `Authorization: Bearer` 调用 ezB API | task-sync / poll / recur-tag / bill-reminder |
| `vikunja_token` | n8n `Settings → Variables` | Vikunja 用户的 API Token（网页「设置 → 令牌」生成） | `Authorization: Bearer` 调用 Vikunja API | task-sync / budget-plan |
| `ezb_cat_expense` | n8n `Settings → Variables` | ezB 支出分类 ID（**字符串**，如 `"1"`） | task-sync 建账时填 `categoryId`（见下方注意） | task-sync |
| `ezb_account_cash_id` | n8n `Settings → Variables` | ezB 现金账户 ID（**字符串**） | `fund:...:cash` 任务记账的目标账户 `sourceAccountId` | task-sync |
| `ezb_account_deposit_id` | n8n `Settings → Variables` | ezB 存款账户 ID（**字符串**） | `fund:...:deposit` 任务记账的目标账户 `sourceAccountId` | task-sync |

> ⚠️ **ID 字段必须按字符串发送**：ezB 源码中 `categoryId`、`sourceAccountId` 绑定为 `,string`（`json:"categoryId,string"`）。在 n8n 变量里填数字会被当成 JSON number 导致绑定失败（400）。务必填带引号的字符串（如 `"1"`）；当前流程用 `={{ $vars.xxx }}` 表达式，n8n 通常会以字符串发送，但若在变量 UI 里直接填了纯数字仍可能踩坑——请填字符串形式。

## 二、与 `.env` 的映射

| 概念 | `.env` 项 | 说明 |
|---|---|---|
| Webhook 密钥 | `WEBHOOK_SECRET` | 该值与上面的 n8n `webhook_secret` **必须是同一个串**；同时 Vikunja 里两个 Webhook 的 Target URL 末尾要补 `?secret=<同一值>`（见 `docs/实施部署手册.md` §6）。三处不一致会导致新 Auth Guard 丢弃所有请求、桥接停摆。 |
| ezB 用户令牌 | （无独立 `.env` 项） | ezB API Token 直接在 n8n `ezb_token` 填，不从 `.env` 读取。 |
| Vikunja 用户令牌 | （无独立 `.env` 项） | 同上，填 n8n `vikunja_token`。 |

> 注：`.env` 中的 `EZB_SECRET_KEY` 是 ezB 的**数据加密密钥**（用于加密数据库中的敏感字段），与这里的 API Token（`ezb_token`）**不是一回事**，请勿混淆。

## 三、填写顺序建议

1. 在 ezB / Vikunja 网页各生成一个 API Token。
2. n8n `Settings → Variables` 新建上述 6 个变量，粘贴对应值（ID 类按字符串填）。
3. 生成 `webhook_secret` 随机串，同时写入 n8n `webhook_secret` 与 `.env` 的 `WEBHOOK_SECRET`，并补到两个 Vikunja Webhook URL 末尾。
4. 导入 5 个 `n8n/*.json`，按需要 Enable（核心 3 个必开；recur-tag / bill-reminder 按需）。
5. 逐步联调（见手册 §B2）：先手动「执行工作流」跑通，再启用 Webhook / 定时。

## 四、ezB 周期交易前置开关

使用「定期扣款」闭环（`recur-tag` + `poll` 回写）前，必须开启 ezB 的周期交易功能：

- 配置项：`enable_scheduled_transaction = true`（默认 `false`；具体环境变量名以你所装 ezB 版本为准，可在 ezB 配置文件或环境变量中设置）。
- 未开启则周期交易无法建立、不会自动过账，整个 recur 闭环不工作。
