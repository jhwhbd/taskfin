# NAS 构建（从源码）前置检查 / 回滚说明 · taskfin

> 适用：把 `docker-compose.yml` 中 `vikunja` / `ezbookkeeping` 从「官方镜像」切换为「从 `vendor/` 修改后源码构建」后的首次部署与后续升级。
> 背景：本项目已对两份上游源码做**品牌化改造**（应用名 / 图标 / PWA 启动图统一改为 TaskFIN），因此不再直接拉取官方镜像，而是用 `docker compose build` 从 `vendor/` 构建。

---

## 0. 一句话结论

- **首次部署**：先单独 `docker compose build vikunja ezbookkeeping`（预计 20–40 分钟、需外网），成功后再 `docker compose up -d`。
- **回滚**：删掉 compose 里这两个服务的 `build:` 块，并把 `image: taskfin-*:local` 改为注释、取消其下方官方镜像行的注释 → 退回官方镜像（界面恢复原厂名/图标）。
- **升级上游**：更新 `vendor/` 后重跑品牌脚本，否则品牌文件会被上游覆盖。

---

## 1. 前置条件（构建前必查）

| 检查项 | 要求 | 不满足的后果 |
|---|---|---|
| **外网可达** | NAS 能访问 `hub.docker.com`、`ghcr.io`、`registry.npmjs.org`、`proxy.golang.org`（Go module 代理） | 拉不到基础镜像 / npm 包 / Go 依赖 → 构建直接失败 |
| **Docker 基础镜像** | 首次会从仓库拉：`node:24.*-alpine`、`golang:1.26.*-alpine`、`ghcr.io/techknowlogick/xgo:go-1.26.x`、`alpine:3.24` | 同上 |
| **磁盘空间** | 构建期需约 **6–10 GB** 临时空间（前端 node_modules + Go 编译缓存 + 多阶段中间层） | 磁盘满 → 构建中断 |
| **CPU / 时间** | DS1618+（Intel Atom C3538，4 核，无 AVX）。前端 pnpm 打包 + 后端 Go（xgo 交叉编译） | 预计 **20–40 分钟**，期间 NAS 负载高，勿同时跑重任务 |
| **ARM/AVX 无关** | C3538 无 AVX/AVX2，仅影响 ML/向量计算；Go/Node 构建不受影响 | 无（仅提醒：别在这台机器跑 Ollama/向量库） |

> ⚠️ `ghcr.io/techknowlogick/xgo` 用于 Vikunja 后端交叉编译，**必须从 ghcr.io 拉**，这是最容易漏的外网依赖。

---

## 2. 推荐构建流程（分步，便于定位失败）

```bash
# 在仓库根目录（含 docker-compose.yml）执行

# 1) 先构建两个品牌化组件（分步便于看日志）
docker compose build vikunja          # 前端 pnpm + 后端 xgo，最慢
docker compose build ezbookkeeping    # 前端 npm + 后端 go（build.sh 已做 git 容错）

# 2) 构建其余官方镜像（NPM/DDNS/n8n，正常拉取，很快）
docker compose build

# 3) 全部就绪后启动
docker compose up -d

# 4) 验证（见 §5）
```

若想一次性构建全部：`docker compose build`（等价于上面 1+2）。

---

## 3. 已知构建风险与处理

| 风险 | 说明 | 处理 |
|---|---|---|
| **B7 ezB `git rev-parse`** | `vendor/ezbookkeeping/build.sh` 原会用 `git rev-parse` 取 commit hash；vendored 副本无 `.git` 会报错。 | ✅ 已修：`COMMIT_HASH="$(git rev-parse --short=7 HEAD 2>/dev/null \|\| echo 'taskfin-branded')"`，静默回退，不影响构建。 |
| **Vikunja 版本来源** | 后端版本来自 `RELEASE_VERSION` 环境变量（compose 已注入 `taskfin`），前端 `src/version.json` 同参；**不依赖 git**。 | 无需处理；若想显示真实版本号，把 compose 中 `RELEASE_VERSION: taskfin` 改为 `v2.5.0`。 |
| **`go vet` / `go test`** | ezB `build.sh` 默认会跑 `go vet` 与单元测试，C3538 上会拖慢；个别测试失败可能导致 `exit 1`。 | 若卡在测试，可临时在 compose `build.args` 加 `SKIP_TESTS: "1"`（需 build.sh 支持，未验证）；或先用官方镜像回滚。 |
| **xgo 镜像拉取** | ghcr.io 偶发限流/不通。 | 重试；或预先 `docker pull ghcr.io/techknowlogick/xgo:go-1.26.x`。 |
| **npm/pnpm 缓存** | 前端构建依赖 npm registry，内网若走代理需配 `.npmrc`。 | 确保 NAS 能直连 `registry.npmjs.org`。 |

---

## 4. 回滚到官方镜像（构建失败或不想要品牌化时）

编辑 `docker-compose.yml`：

**Vikunja 块**
```yaml
  vikunja:
    # image: vikunja/vikunja:${VIKUNJA_VERSION}   ← 取消这行注释
    # image: taskfin-vikunja:local                ← 把这行改成注释
    # build:                                      ← 删除整个 build: 块
    #   context: ./vendor/vikunja
    #   dockerfile: Dockerfile
    #   args:
    #     RELEASE_VERSION: taskfin
```

**ezBookkeeping 块** 同理（官方镜像行 `mayswind/ezbookkeeping:${EZB_VERSION}`）。

然后：
```bash
docker compose up -d        # 会拉取官方镜像（需外网）
```
> ⚠️ 回退后界面恢复 **Vikunja / ezBookkeeping 原厂名称与图标**——这是预期权衡，不是 bug。

---

## 5. 构建后验证（确认品牌化生效）

1. 浏览器打开 `https://tasks.<你的域名>` → 标签/页内标题应为 **TaskFIN**，favicon 为紫色 T-FIN。
2. 打开 `https://fin.<你的域名>` → 同上。
3. 移动端「添加到主屏幕」→ 主屏图标为 TaskFIN；iOS 启动图为白底 T-FIN。
4. 注册/登录后任意非英语语言界面，应用名仍为 TaskFIN（已改全部语言 token）。
5. 触发一封系统邮件（如密码重置）→ 发件人显示名应为 TaskFIN。

---

## 6. 升级上游版本（保留品牌）

```bash
# 1) 拉取新版上游到临时目录
git clone --depth 1 https://github.com/go-vikunja/vikunja.git /tmp/vikunja
git clone --depth 1 https://github.com/mayswind/ezbookkeeping.git /tmp/ezb

# 2) 用新版覆盖 vendor/（先备份你的品牌改动！）
#    cp -r /tmp/vikunja/. vendor/vikunja/   （注意保留 .git 外的全部，勿带 /tmp 的 .git）
#    cp -r /tmp/ezb/.   vendor/ezbookkeeping/

# 3) 更新 vendor/SOURCES.md 中的哈希与日期

# 4) 重新执行品牌化（图标 + 启动图 + 名称）
node scripts/gen-icons.cjs
node scripts/gen-splash.cjs
#    名称字符串改动见 README「品牌化」段，需按上游变动重新应用。

# 5) 重新构建
docker compose build vikunja ezbookkeeping && docker compose up -d
```

> ⚠️ **`scripts/check-vendor.sh` 行为说明**：该脚本只比对「上游 HEAD 是否前进」（记录来自 `vendor/SOURCES.md`），**不哈希本地文件**，因此你的品牌修改**不会**触发误报。但当它提示「落后」时，意味着上游有更新；按上面 §6 步骤操作即可，**切勿直接 `rm -rf vendor && cp`**（会抹掉品牌文件）。
