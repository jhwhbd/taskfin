# Vendored Third-Party Source Code

本目录收录本项目依赖的两个上游开源项目的**完整源代码快照**，目的是在万一上游仓库关闭或不可达时，本项目仍可自包含地构建、部署与维护，不依赖外部托管。

## 收录清单（vendor 于 2026-08-18 刷新至上游最新 main）

### Vikunja
- 上游仓库：<https://github.com/go-vikunja/vikunja>
- 许可证：**AGPL-3.0**（强 copyleft，全文见 `vendor/vikunja/LICENSE`）
- Vendor 版本：`e61c81cc54a0f035baeaad1ea63066294872e028`（2026-08-17 23:07 北京时间，main 最新提交）
- 说明：前后端合一的 monorepo（Go 后端 + Vue 前端）。本快照为 shallow clone 去除 `.git` 后的纯源码，**未做任何修改**。

### ezBookkeeping
- 上游仓库：<https://github.com/mayswind/ezbookkeeping>
- 许可证：**MIT**（宽松，全文见 `vendor/ezbookkeeping/LICENSE`）
- Vendor 版本：`0461abcc94b5f7e337d4736bc6f52d77ab238deb`（2026-08-18 00:28 北京时间，main 最新提交）
- 说明：轻量自托管个人记账应用（Go + TypeScript/Vue）。本快照为 shallow clone 去除 `.git` 后的纯源码，**未做任何修改**。

## 许可证与合规义务

- **Vikunja（AGPL-3.0）**：若你修改其源码，并**通过网络交互方式向他人提供该软件的服务**（例如自托管且允许家庭成员/其他用户通过网络访问），依据 AGPL 第 13 条，你必须向这些用户提供你修改后的对应源代码。纯自用、不对外部提供网络服务时一般不触发该义务。本项目当前为未修改快照。
- **ezBookkeeping（MIT）**：可自由使用、修改、再分发，仅需保留原始版权与 LICENSE 声明。

> ⚠️ 本项目根目录 `docker-compose.yml` 直接引用官方 Docker 镜像（`vikunja/vikunja`、`mayswind/ezbookkeeping`）。`vendor/` 中的源码是**保险副本**：仅在官方镜像/仓库不可用时，用于自行从源码构建镜像，而非日常运行的依赖。

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
