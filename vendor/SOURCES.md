# Vendored Third-Party Source Code

本目录收录本项目依赖的两个上游开源项目的**完整源代码快照**，目的是在万一上游仓库关闭或不可达时，本项目仍可自包含地构建、部署与维护，不依赖外部托管。

## 收录清单（vendor 于 2026-08-18 刷新至上游最新 main）

### Vikunja
- 上游仓库：<https://github.com/go-vikunja/vikunja>
- 许可证：**AGPL-3.0**（强 copyleft，全文见 `vendor/vikunja/LICENSE`）
- Vendor 版本：`e61c81cc54a0f035baeaad1ea63066294872e028`（2026-08-17 23:07 北京时间，main 最新提交）
- 说明：前后端合一的 monorepo（Go 后端 + Vue 前端）。本快照为 shallow clone 去除 `.git` 后的纯源码，**已做 TaskFIN 品牌化改造**（名称/图标/启动图/多语言/部分后端文案，详见下方「品牌化改造清单」）。

### ezBookkeeping
- 上游仓库：<https://github.com/mayswind/ezbookkeeping>
- 许可证：**MIT**（宽松，全文见 `vendor/ezbookkeeping/LICENSE`）
- Vendor 版本：`0461abcc94b5f7e337d4736bc6f52d77ab238deb`（2026-08-18 00:28 北京时间，main 最新提交）
- 说明：轻量自托管个人记账应用（Go + TypeScript/Vue）。本快照为 shallow clone 去除 `.git` 后的纯源码，**已做 TaskFIN 品牌化改造**（名称/图标/启动图/多语言/部分后端文案，详见下方「品牌化改造清单」）。

## 许可证与合规义务

- **Vikunja（AGPL-3.0）**：若你修改其源码，并**通过网络交互方式向他人提供该软件的服务**（例如自托管且允许家庭成员/其他用户通过网络访问），依据 AGPL 第 13 条，你必须向这些用户提供你修改后的对应源代码。本项目**已修改**（TaskFIN 品牌化），且本仓库即包含修改后源码，AGPL 第 13 条义务已满足；纯自用不对外服务时亦无额外负担。
- **ezBookkeeping（MIT）**：可自由使用、修改、再分发，仅需保留原始版权与 LICENSE 声明。

> ⚠️ 本项目根目录 `docker-compose.yml` 的 **Vikunja / ezBookkeeping 已改为从本 `vendor/` 源码 `build:`**（镜像 tag 为 `taskfin-vikunja:local` / `taskfin-ezbookkeeping:local`），`vendor/` 是**日常运行的构建源**而非仅保险副本。上游仓库不可用时仍可用 `vendor/` 自行构建；若想退回官方镜像，删掉 compose 中对应 `build:` 块并取消官方镜像注释即可（详见 `docs/NAS构建与回滚.md`）。

### TaskFIN 品牌化改造清单（vendor 已应用）
- **名称**：界面/邮件/通知中的 "Vikunja" / "ezBookkeeping" 均替换为 "TaskFIN"（含 30+ 语言文件、Vikunja 后端邮件发件人/User-Agent、ezB 后端 `ApplicationName` 常量与 20 语言 `AppName`）。
- **图标 / 启动图**：生成紫色（#6C5CE7）"T-FIN" SVG 并替换前后端 favicon、各尺寸图标；ezBookkeeping 42 张设备启动图（`vendor/ezbookkeeping/public/img/splash_screens/`）全部重绘为 TaskFIN 品牌。
- **保留项**：上游 Powered by / GitHub 链接、事实性引用（如"导入到 Vikunja"）、版权与许可证署名均原样保留，以满足 AGPL-3.0 / MIT 合规。
- **注意**：品牌化文件不计入 `scripts/check-vendor.sh` 的哈希校验（该脚本会跳过本地品牌文件）；上游前进并需重新 vendor 时，需在新快照上重做品牌化（或仅合并非品牌文件）。
- **重跑品牌脚本的前置条件（P8）**：`scripts/gen-icons.cjs` 与 `scripts/gen-splash.cjs` 依赖 `opentype.js`、`@resvg/resvg-js`、`png-to-ico`，仓库根 `package.json` 已声明；重跑前需先 `npm install`（安装到本地 `node_modules`）。首次部署因品牌已烤进 vendor，可跳过；仅在上游升级重做品牌化时才需要。

## 如何更新到上游新版本

若需同步上游更新，重新拉取并覆盖即可（保留 `.git` 仅用于取最新，取完即删）：

```bash
# Vikunja
git clone --depth 1 https://github.com/go-vikunja/vikunja.git /tmp/vikunja
rm -rf /tmp/vikunja/.git
rm -rf vendor/vikunja && cp -r /tmp/vikunja vendor/vikunja

# ezBookkeeping
git clone --depth 1 https://github.com/mayswind/ezbookkeeping.git /tmp/ezb
rm -rf /tmp/ezb/.git
rm -rf vendor/ezbookkeeping && cp -r /tmp/ezb vendor/ezbookkeeping
```

更新后请同步修改本文件中的 commit 哈希与日期。
