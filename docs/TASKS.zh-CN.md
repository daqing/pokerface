# PokerFace 开发任务清单

> 依据 `README.md` 的 Architecture、Pull Sequence 与 Roadmap 拆解。
> 目标：把开发计划拆成 1-3 小时可独立完成、可独立验收的 Task，适合利用空闲时间逐项推进。

[English](TASKS.md)

## 1. 使用方式

- 每个 Task 对应一个可独立合并的改动，原则上一次提交 / 一个 PR 只做一个 Task。
- 开工前从 `develop` 切分支，例如 `feat/t1.3-ref-parser`；不要直接改 `main`。
- 完成一个 Task 时，同时更新本文的进度表，并把对应条目标成 `[x]`。
- 每个 Task 的验收命令必须可复制执行；至少跑 `emo build` 和相关 `emo test`。
- 一个 Task 如果超过 4 小时还做不完，说明拆得不够细，先补拆再继续。
- 编号规则：`T<里程碑>.<序号>`，按依赖顺序递增；新增任务追加编号，不复用已删除的编号。

### 完成定义（DoD）

- [ ] `emo build` 通过，无编译错误。
- [ ] 新增行为有测试；测试按项目现有风格放在 `test/`。
- [ ] 涉及 CLI、配置或协议的行为，同步更新 `docs/` 或本 Task 指定的规范文档。
- [ ] 不引入未在 `package.emo` 中 pin 的依赖。
- [ ] 不把 token、密钥、真实用户数据写进仓库、日志或测试 fixture。
- [ ] 更新本 Task 的状态与备注（实际耗时、踩坑、后续项）。

## 2. 范围与里程碑

本计划只拆解 M1、M2、M4。M3 不在本次范围内，本文不臆造其内容；为保证 `M1 + M2 + M4` 能独立走通端到端，README 路线图第 5 项（运行时导入）放进 M1，第 6 项（构建触发 / CI）放进 M4。

| 里程碑 | 主题 | 覆盖 README Roadmap | 完成标志 | 粗估 |
| --- | --- | --- | --- | --- |
| M1 | 客户端闭环：解析 + 拉取 + 导入 | 1、2、5 | `pokerface resolve` 与 `pokerface pull` 可对本机 Registry 工作，镜像能 `docker run` | 约 35-40h |
| M2 | 分发层 MVP：Registry + 对象存储 | 3、4 | 一条 `docker compose up` 起服务，能推送 / 拉取 Manifest 与 Blob，Blob 走预签名 CDN URL | 约 45-55h |
| M4 | 构建、CI 与交付 | 6、7 | 示例仓库可通过 `pokerface build` 构建推送，CI 模板可用，文档站与端到端脚本完成 | 约 40-50h |

建议按每周 4-6 小时的节奏安排；按上述粗估，MVP 大约需要 5-7 个月的空闲时间投入。实际排期请预留 30%-50% 的调研和返工余量。

## 3. 先冻结的接口决策

下面这些决策会影响多个 Task，建议在 M1 前半段一次性定下来；后续如需修改，单独记 ADR。

| 编号 | 决策 | 默认方案 | 落地 Task |
| --- | --- | --- | --- |
| D1 | 实现语言与运行时 | Emo，`c` target；优先使用标准库 `http` / `httpd` / `yaml` / `json` / `sqlite3` / `crypto` / `os` / `slog` | T1.2、T2.1 |
| D2 | 构建元数据文件 | 应用仓库根目录提交 `pokerface.yaml` 与 CI 生成的 `pokerface.lock.yaml` | T1.4、T1.5 |
| D3 | 仓库引用语法 | `<host>/<owner>/<repo>[:<tag>]`，默认 `latest`；同时接受 `https://` 与 `git@` 形式 | T1.3 |
| D4 | Blob 访问方式 | Registry 保存 Manifest；Blob GET 返回 307 + S3/MinIO 预签名 URL；客户端下载后校验 digest | T2.9、T1.11 |
| D5 | 运行时导入 | 先组装本地 OCI Layout，再调用 `skopeo` 导入 `docker-daemon` / `containers-storage`；无 skopeo 时给出明确错误 | T1.13 |
| D6 | 认证 | Bearer Token，`pull` / `push` scope；v0.1 用配置文件的预共享账号签 Token，不接 OAuth | T2.14、T1.10 |
| D7 | 构建触发 | v0.1 由 CI 驱动（push / tag / workflow_dispatch），不做自建 webhook 服务 | T4.5、T4.6 |
| D8 | 元数据存储 | SQLite 存仓库、Manifest、Tag、上传会话；Blob 存 S3/MinIO；本地开发用文件系统后端 | T2.2、T2.6 |
| D9 | 兼容性目标 | 先实现 OCI Distribution Spec 的必要子集，并用 `oras` / `skopeo` 做冒烟；不承诺完整 Docker 客户端兼容 | T2.19 |
| D10 | 文档形态 | Markdown 静态站点起步，优先 GitHub Pages；需要搜索时再引入 VitePress | T4.8 |

## 4. M1：客户端闭环

### 4.1 目标与退出标准

把 README 的 Pull Sequence 前半段做成可用的 CLI：解析仓库引用，`tag -> Commit -> Digest`，拉取 Manifest 与 Blob，校验后导入本地运行时。

退出标准：

- `pokerface resolve github.com/acme/app:latest` 能打印完整的解析链路。
- `pokerface pull` 能对本地测试 Registry 完成拉取并导入 Docker / podman。
- Git 解析失败、Manifest 失败、Blob 校验失败、导入失败四类场景都有明确行为和退出码。
- 拉取全过程不访问 `registry-1.docker.io`。
- `emo test` 通过，`scripts/e2e-m1.sh` 可在干净环境运行。

### 4.2 任务总览

| 状态 | ID | 任务 | 依赖 | 预估 |
| --- | --- | --- | --- | --- |
| [x] | T1.1 | CLI 骨架与命令路由 | 无 | 1-2h |
| [x] | T1.2 | Emo 运行时能力验证与依赖锁定 | T1.1 | 2h |
| [x] | T1.3 | 仓库引用解析 | T1.1 | 1-2h |
| [x] | T1.4 | `pokerface.yaml` v0.1 规范与解析 | T1.2 | 2-3h |
| [x] | T1.5 | `pokerface.lock.yaml` v0.1 规范与解析 | T1.2 | 2h |
| [x] | T1.6 | Git ref 解析：tag / branch / commit | T1.3 | 2-3h |
| [x] | T1.7 | Git 元数据读取与镜像缓存 | T1.6、T1.5 | 3h |
| [x] | T1.8 | 配置、凭据与 XDG 路径 | T1.1 | 2h |
| [x] | T1.9 | `resolve` 命令串联 | T1.4-T1.8 | 2h |
| [x] | T1.10 | Registry 认证与 Manifest 客户端 | T1.5、T1.8 | 3h |
| [x] | T1.11 | Blob 下载器：重试、校验、续传 | T1.10 | 3-4h |
| [ ] | T1.12 | OCI 镜像布局组装 | T1.10、T1.11 | 2-3h |
| [ ] | T1.13 | 运行时导入适配 | T1.12 | 3h |
| [ ] | T1.14 | `pull` 命令串联与失败回退 | T1.9-T1.13 | 3h |
| [ ] | T1.15 | 本地缓存与离线模式 | T1.7、T1.14 | 2-3h |
| [ ] | T1.16 | 错误模型、退出码与日志 | T1.1 | 2h |
| [ ] | T1.17 | M1 测试基线、E2E 脚本与规范文档 | T1.1-T1.16 | 2-3h |

### 4.3 任务详情

#### T1.1 CLI 骨架与命令路由

**目标**：建立可构建、可运行的 CLI，包含 `resolve`、`pull`、`build`、`config`、`cache`、`version` 子命令与全局参数 `--config`、`--verbose`、`--json`。

**交付**：`main.emo`、`src/cli.emo`、帮助文本、退出码常量；未实现的子命令返回明确的“未实现”错误，而不是崩溃。

**验收**：`emo build` 通过；`pokerface --help` 与 `pokerface version` 正常；未知命令退出码为 2；`emo test` 仍通过。

**依赖**：无 · **预估**：1-2h

> **笔记**（2026-11-17，约 1h）：完成。`main.emo` 是薄入口（`src.cli.route(os.argv())` + `os._exit`）；`src/cli.emo` 承载命令路由、帮助文本、`Flags` 类与退出码常量（0 成功 / 1 失败 / 2 用法错误）。未实现的子命令向 stderr 输出“未实现”提示并退出 1；`version` 支持 `--json`；无参数、未知命令/未知选项均退出 2。踩坑：本地模块按路径引用（是 `src.cli` 而不是 `cli`）；解析后未使用的局部变量会在 C 层报 `-Wunused-but-set-variable`，所以解析出的参数通过 `Flags` 传入 handler。后续：T1.8 读取 `Flags.config`，T1.16 接通 verbose 日志与完整退出码表，T4.10 把 `docs/cli.md` 扩成完整参考。

#### T1.2 Emo 运行时能力验证与依赖锁定

**目标**：验证后续实现依赖的标准库能力：YAML / JSON 编解码、HTTPS 请求、子进程、SHA-256、文件与临时目录。重点确认 `http` 客户端“不自动跟随重定向”和“响应体整体读入内存”的限制。

**交付**：`test/capabilities.emo`（或 `spike/` 下的可执行验证）、`package.emo` 依赖声明、`package.lock`、`docs/notes/runtime-capabilities.md`。

**验收**：`emo build` + `emo test` 通过；验证程序能完成一次 HTTPS GET、一次 `git --version` 子进程、一次 SHA-256；笔记中记录大文件下载与重定向的应对方案（必要时在 T1.11 基于 `net` 自行流式下载）。

**依赖**：T1.1 · **预估**：2h

> **笔记**（2026-11-17，约 1.5h）：完成。目标能力全部验证通过——SHA-256（RFC 向量）、子进程 fork/execvp/waitpid 加管道捕获、HTTPS GET、YAML/JSON 编解码、文件 IO、临时目录；`emo test` 25/25。关键结论：`http` 确实不跟随重定向（301 原样返回）且整个 body 进内存——T1.10 用 `http` 处理 manifest/token，T1.11 改用 `net` 流式下载 blob 并手动处理 307。影响后续任务的踩坑：裸 `.` 的 YAML 标量会解析成 `YamlFloat`（编码回去变 `0.0`），正好命中 `pokerface.yaml` 的 `context: .`——T1.4 必须要求加引号或拒绝浮点 context。详见 `docs/notes/runtime-capabilities.md`。

#### T1.3 仓库引用解析

**目标**：把用户输入解析成结构化引用：Git URL、仓库标识、tag / branch / commit、默认 `latest`。支持 `github.com/acme/app:latest`、`https://github.com/acme/app.git:v1.2.0`、`git@github.com:acme/app.git:main`。

**交付**：`src/ref.emo` + 表驱动测试。规范化输出至少包含 `host`、`owner`、`repo`、`git_url`、`ref`。

**验收**：覆盖合法 / 非法 / 带 `.git` / 带端口 / 带默认 tag 的用例；不发起任何网络请求；错误信息指出具体字段。

**依赖**：T1.1 · **预估**：1-2h

> **笔记**（2026-11-18，约 1h）：完成。`src/ref.emo` 零依赖解析 D3 三种形式；ref 在“最后一个后面不带 `/` 的冒号”处切分，因此 `host:port` 与 `:ref` 可以共存；`git_url` 统一归一化为 `https://<host>[:<port>]/<owner>/<repo>.git`。`test/ref.emo` 共 35 个表驱动用例（12 合法 + 23 非法），非法表断言错误信息指明出错字段。踩坑：类名不能与模块名大小写不敏感地相同——`src/ref.emo` 里声明 `class Ref` 会让签名中的裸 `Ref` 与 `Ref.new` 解析不一致，已改名为 `Reference`；数组字面量不接受尾逗号。后续：完整 git refname 规则（前导 `.`、`.lock`、`@{`）移到 T1.6；v0.1 按设计拒绝子群组路径（`gitlab.com/g/s/p`）。

#### T1.4 `pokerface.yaml` v0.1 规范与解析

**目标**：定义应用仓库中的构建配置，覆盖镜像名、构建上下文、Dockerfile、target、平台、构建参数、tag 规则与 Registry 地址。建议结构：

```yaml
version: 1
image: registry.example.com/acme/app
build:
  context: .
  dockerfile: Dockerfile
  target: runtime
  platforms: [linux/amd64]
  args:
    NODE_ENV: production
tags:
  - latest
  - "{{ commit.short }}"
registry:
  url: https://registry.example.com
```

tag 规则至少要支持 `latest`、`{{ commit.short }}`、`{{ git.tag }}`、`{{ branch }}`、`{{ version }}` 的占位符。

**交付**：`docs/spec/pokerface-yaml.md`、`src/config.emo`、`examples/pokerface.yaml`、解析与校验测试。

**验收**：示例文件可解析；缺少 `version` / `image` / `build.context` 时报错并指出路径；非法平台名、重复 tag、未闭合占位符被拒绝；规范文档包含完整字段表。

**依赖**：T1.2 · **预估**：2-3h

> **笔记**（2026-11-18，约 2h）：完成。`src/config.emo` 解析并校验 v0.1 全部字段，错误信息带路径（`pokerface.yaml: build.context: …`）；version 为 1 时拒绝未知字段；tags 支持字面量与 `{{ commit.short }}`/`{{ git.tag }}`/`{{ branch }}`/`{{ version }}` 模板。T1.2 的踩坑实测命中：裸 `context: .` 解析成 `YamlFloat`，被拒绝并附引号提示，所以 `examples/pokerface.yaml` 用 `context: "."`。共 25 个测试用例（示例文件、最小配置默认值、7 个合法变体、25 行非法表）；`emo test` 32/32。踩坑：`is()` 窄化只覆盖 `if` 分支本身，解析器统一写成 `if value.is(…) { …主体… } return error` 的形状；`substring(start, len)` 越界会抛异常——取两字符窗口前先用 `i + 2 <= len` 守卫。后续：模板渲染在 T4.1 落地；平台支持集随真实构建能力再扩充。

#### T1.5 `pokerface.lock.yaml` v0.1 规范与解析

**目标**：定义 CI 构建后写回 Git 的元数据，让拉取端只依赖 Git 就能得到镜像 digest。建议结构：

```yaml
version: 1
commit: 0123456789abcdef0123456789abcdef01234567
source: github.com/acme/app
generated_at: "2026-11-17T12:00:00Z"
images:
  - image: registry.example.com/acme/app
    tags: [latest, sha-01234567]
    digest: sha256:...            # top-level index or single-platform manifest
    manifest_digest: sha256:...   # selected platform manifest
    platforms: [linux/amd64]
    builder: buildkit
```

**交付**：`docs/spec/pokerface-lock.md`、`src/lockfile.emo`、示例文件、解析 / 编码测试。

**验收**：解析后可稳定重编码（字段顺序确定）；`commit` 必须为完整 SHA；digest 格式校验；重复 tag 被拒绝；未知 `version` 明确报错；`generated_at` 不参与任何 digest 校验。

**依赖**：T1.2 · **预估**：2h

> **笔记**（2026-11-18，约 2h）：完成。`src/lockfile.emo` 解析并编码 v0.1 全部字段；`source` 复用 `src.ref.parse` 并归一化为裸 `host/owner/repo` 形式（source 里带 ref 会被拒绝）；lock 的 tags 只接受已渲染字面量——`{{ 占位符 }}` 会被拒绝并提示回 `pokerface.yaml`。编码器固定字段顺序并省略空的可选字段，`encode(load(text))` 字节级稳定；`generated_at` 仅是元数据，两条只差该字段的 lock 解析出相同 digest（有测试钉住）。镜像/平台校验通过新增的无前缀 `config.check_image`/`check_platform` 与 T1.4 共用。7 个测试约 40 个用例；`emo test` 39/39。踩坑重申：具体类方法（`entries`）需要窄化后的接收者，所以 `parse_image_entry` 拆成 `is()` 闸门 + 接收具体类型 `yaml.YamlObject` 的内层 `parse_image_object`。

#### T1.6 Git ref 解析：tag / branch / commit

**目标**：通过 `git ls-remote` 把 tag / branch / 短 SHA / 完整 SHA 解析成 commit SHA。必须处理 annotated tag 的 `^{}` 引用，并识别默认分支。

**交付**：`src/git.emo`、可注入的命令执行器（便于测试）、临时 Git 仓库 fixture。

**验收**：轻量 tag、annotated tag、branch、HEAD、完整 SHA、短 SHA 均有测试；不存在的 ref 返回明确错误；子进程有超时；参数以数组传递，不经过 shell 拼接。

**依赖**：T1.3 · **预估**：2-3h

> **笔记**（2026-11-18，约 2.5h）：完成。`src/git.emo` 以可注入的 `CommandRunner` 接口暴露 `resolve(runner, git_url, wanted, timeout)`；wanted 语义钉在 docs/cli.md——`latest` 解析为默认分支 HEAD（一次 `--symref` 调用），annotated tag 剥离到 `^{}` commit，分支/tagName 同名冲突报 ambiguous，`refs/...` 是精确逃生通道，完整 SHA 直接放行（存在性在 T1.7 拉取时校验）。重要发现：**`os.waitpid` 会阻塞整个调度器**——父进程等待期间 `time.after` 看门狗根本不跑，所以 `RealRunner` 用双 fork 看门狗（子进程再 fork 孙进程，孙进程睡到 deadline 后杀掉子进程；父进程随意阻塞）。实测：0.3s 超时在 ~0.30s 杀掉 2s 的 sleep；快命令零额外延迟。测试共 14 个——fixture 仓库（轻量/annotated tag、branch、HEAD、完整/短 SHA、缺失、歧义、latest）经 git 子进程建在 TMPDIR（留给系统清理），另有 FakeRunner 逻辑测试。测试抓出的坑：ls-remote 循环里提前 `return HEAD` 对任何 wanted 都命中——条件必须是 `wanted == "HEAD" && name == "HEAD"`。

#### T1.7 Git 元数据读取与镜像缓存

**目标**：在 `~/.cache/pokerface/git/<hash>` 维护 bare 镜像，按需 fetch 指定 ref / commit，再用 `git show <sha>:pokerface.lock.yaml` 读取元数据。commit 未被服务器广告时，先 fetch 对应 ref 再取 commit。

**交付**：`src/git_cache.emo`、缓存目录布局说明、首次拉取 / 离线读取 / 并发拉取的测试。

**验收**：首次读取后断网仍可读到同一 commit 的 lock；仓库不存在、文件不存在、YAML 非法分别报错；并发执行不会写坏缓存；不修改用户工作区。

**依赖**：T1.6、T1.5 · **预估**：3h

> **笔记**（2026-11-18，约 2.5h）：完成。`src/git_cache.emo` 在 `<cache_root>/git/<sha256 前缀>` 下为每个 URL 保留一个裸镜像并写 `source-url` 标记；读取走 `git show <commit>:pokerface.lock.yaml`，未命中则 fetch 后重试。离线保证是结构性的：show 快路径绝不触发 fetch（RecordingRunner 断言新增日志里没有 fetch）。ref 提示路由 fetch：完整 SHA → 按 SHA 拉取（失败时错误提及 `uploadpack.allowAnySHA1InWant`——本地传输允许）；`refs/...` → 精确 ref；名字 → 先分支 refspec 再 tag refspec；未知 → 全部 heads+tags。RealRunner 现在同时捕获 stderr，`git show` 的 "does not exist" 文本可用于分类。并发需要两处有限重试：竞态的 `git init --bare` 会输掉 mkdir 竞争（每轮复查 HEAD），并发 fetch 会撞锁文件（对 "File exists" 重试）。测试 10 个，含真实 fork 子进程与父进程在同一全新缓存上赛跑、工作目录快照对照；`emo test` 63/63。布局文档：docs/notes/git-cache-layout.md。

#### T1.8 配置、凭据与 XDG 路径

**目标**：建立配置加载顺序和凭据管理。路径优先级：`--config` > `POKERFACE_CONFIG` > `$XDG_CONFIG_HOME/pokerface/config.yaml` > `~/.config/pokerface/config.yaml`。环境变量覆盖文件配置。

**交付**：`src/settings.emo`、`docs/spec/config.md`、优先级测试、日志脱敏测试。

**验收**：CLI 参数 > 环境变量 > 配置文件 > 默认值；token 不出现在 `--verbose` 日志；配置文件权限过宽时给出警告；缓存目录可通过 `POKERFACE_CACHE_DIR` 覆盖。

**依赖**：T1.1 · **预估**：2h

> **笔记**（2026-11-18，约 2h）：完成。`src/settings.emo` 解析配置路径（`--config` > `POKERFACE_CONFIG` > XDG > `~/.config`，显式指定的文件必须存在），再以 `POKERFACE_REGISTRY_URL` / `POKERFACE_REGISTRY_TOKEN` / `POKERFACE_CACHE_DIR` 覆盖文件值。环境读取走可注入的 `EnvSource`（RealEnv/FakeEnv），测试不会污染进程环境——测试共享一个进程，`os.setenv` 会跨测试泄漏。权限检查经 runner 跑 `stat`（用 `uname` 区分 BSD/GNU），group/other 有读位即告警，stat 失败静默不告警。`redact()` 输出 `<redacted:<len>>`，`summary()` 是 verbose 输出形态——token 永不出现。14 个测试；`emo test` 79/79。踩坑：类不能叫 `Settings`（与模块 settings 撞名，T1.3 规则重现），改为 `AppSettings`；`os.mkdir` 不建父目录——fixture 需逐级创建。

#### T1.9 `resolve` 命令串联

**目标**：把引用解析、Git commit 解析、lock 读取串起来，输出 `ref -> commit -> image -> digest`。支持 `--json`、`--platform`、`--verbose`。

**交付**：`src/commands/resolve.emo`、测试、`docs/cli.md` 中的 `resolve` 示例。

**验收**：对 fixture 仓库输出稳定；`--json` 字段固定且可被脚本消费；lock 中没有匹配镜像 / 平台时非零退出；Git 失败不读取旧缓存。

**依赖**：T1.4-T1.8 · **预估**：2h

> **笔记**（2026-11-18，约 2.5h）：完成。`src/commands/resolve.emo` 串联 ref → commit → lock → image → digest，支持 `--json`（字段顺序固定）与人类可读输出；多镜像 lock 明确报错，缺 ref/lock/config 各自退出 1 并带原因；git 失败绝不回退旧缓存（同 commit 的缓存命中不需要网络，保持离线可用）。两个结构性调整：(1) resolve→cli 的引用构成模块环，Flags/eprint/退出码抽到新的 `src/common.emo`——命令 handler 依赖 common，永不依赖路由器；(2) 引用新增本地路径形式（`/…`、`./…`、`../…` → git_url 保留原始路径），因为本地 e2e fixture 是 T1.17 离线脚本的硬需求。两个加载器深坑耗了不少时间：测试文件镜像被测路径（test/commands/resolve.emo）会触发 E5003，顶层 `const X = src.<mod>.new(...)` 同样会触发——跨模块构造必须放进 def 里（test/resolve_cmd.emo 顶部注释记录了这两条）。顺手修复：lockfile.encode 给 `commit:` 加引号，全数字 SHA 也能安全往返。用真实二进制对本地 bare origin 做了端到端验证（人类输出 + json + not-found 路径）；`emo test` 90/90。

#### T1.10 Registry 认证与 Manifest 客户端

**目标**：实现 OCI Registry 客户端的基础能力：`GET /v2/` 探测、解析 `WWW-Authenticate`、获取 Bearer Token、按 tag / digest 获取 Manifest、处理 OCI Index 并按平台选择子 Manifest、校验 `Docker-Content-Digest`。

**交付**：`src/registry.emo`、mock Registry 测试、支持的 media type 列表。

**验收**：401 -> 取 token -> 重试成功；404 / 5xx / 超时有明确错误；多架构 Index 能选中目标平台；Manifest 字节与 digest 一致；所有请求只发往配置的 Registry 域名；不自动跟随重定向。

**依赖**：T1.5、T1.8 · **预估**：3h

> **笔记**（2026-11-18，约 2.5h）：完成。`src/registry.emo` 以可注入 `Transport`（真实 HttpTransport + 离线 MockTransport）实现了全部验收点：探测 → 401 → `WWW-Authenticate` Bearer 解析（realm/service/scope，百分号编码）→ 取 token → 验证探测；按 tag/digest 拉 manifest 并常数时间比对 `Docker-Content-Digest`（不匹配时报出两个 digest）；401 舞步后重试一次，且重试**重建 headers**（第一版复用了 dance 前的 header 数组，静默重发了空 token——被 mock 抓住）；index 平台选择，未命中时列出可用平台；3xx 是硬错误并带 Location；mock 断言所有请求只发往 registry 或 auth 域名。媒体类型表在 docs/spec/registry-client.md。踩坑：client 的 token 可变性需要 `Box`（类字段 init 后冻结）；`Json.get` 对缺失键直接抛异常而 Emo 无 catch，所有可选成员走扫描式 `json_member`；反向 `if !x.is(...)` 守卫不触发窄化——只能正向分支包裹；测试签名里的类型路径不能用 const 别名（`reg.Client` 不行，`src.registry.Client` 才行）。

#### T1.11 Blob 下载器：重试、校验、续传

**目标**：按 Manifest 中的 descriptors 下载 config 与 layers，支持并发上限、指数退避重试、Range 续传、SHA-256 与 size 校验、临时文件清理。

**交付**：`src/blob.emo`、mock CDN 测试、进度输出。

**验收**：模拟 500 / 超时 / 中断后可重试成功；损坏 Blob 被拒绝且不进入 OCI Layout；服务器不支持 Range 时自动退回完整下载；失败后临时文件被清理；大层下载不会导致不可接受的内存占用（若 `http` 限制无法满足，在此 Task 内改用 `net` 流式实现并记录）。

**依赖**：T1.10 · **预估**：3-4h

> **笔记**（2026-11-18，约 3h）：完成。**T1.2 记录的决策在此落地：blob 走 `net` 流式**——`HttpBlobTransport` 手写 HTTP/1.1（按 scheme 走 TLS/明文、Connection: close、支持 Content-Length 与 chunked body，close-delimited 作为已记录的窄场景直接拒绝），大层不再整块进内存。预签名重定向最多跟随 3 跳（D4 机制；绝对 Location，与真实 CDN 一致）。重试/续传：`.part` + `.meta` 偏移 sidecar、Range 续传、服务器对 Range 回 200 时自动退回全量、指数退避（重试次数与基础延迟为参数）、4xx 归类为永久错误不重试、`crypto.sha2.new()` 增量摘要 + 大小校验、`os.rename` 提交——损坏字节进不了布局，每条失败路径都清理临时文件。**并发上限延期**：Emo 的 Box 跨进程是快照语义，共享信号量需要消息传递的 token 进程；顺序版 `download_all_blobs` 保证内存有界、顺序确定，并行形态记为后续任务（候选：T1.14 接线或独立任务）。测试 15 个——mock 故障注入（open 失败、流中掉线并精确续传偏移、Range 回退、403 不重试、损坏、大小不符、清理）加**真实本地 httpd 服务器**腿（全量、206 续传、307 绝对重定向）跑真 net 栈；`emo test` 122/122。踩坑：`TcpConn` 是裸内置类型（没有 `net.TcpConn` 路径）；`var` 用元组字面量初始化会钉死该元组类型——`var conn_result` 要用 `net.connect(...)` 初始化而不是 `(R.error, "...")`；一行 `if` 表达式不能嵌进二元运算（先绑定 const）；`while true` 循环需要补一个不可达的尾 `return` 才能过 E4017。

#### T1.12 OCI 镜像布局组装

**目标**：把 Manifest、config、layers 写成标准 OCI Layout：`oci-layout`、`index.json`、`blobs/sha256/<hex>`，并在 `index.json` 中写入 tag 注解。

**交付**：`src/oci.emo`、fixture Manifest、布局校验测试。

**验收**：`skopeo inspect oci:<dir>` 可读取（本机有 skopeo 时）；所有 descriptor 的 digest / size 与实际文件一致；缺少 Blob 时明确报错；支持 `--keep` 保留临时目录。

**依赖**：T1.10、T1.11 · **预估**：2-3h

#### T1.13 运行时导入适配

**目标**：把 OCI Layout 导入本地运行时。优先 `skopeo copy oci:<dir> docker-daemon:<image>:<tag>`；podman 使用 `containers-storage:`；containerd 使用 `oci-archive` + `ctr images import`。检测可用工具并给出清晰提示。

**交付**：`src/runtime.emo`、支持矩阵文档、命令构造与错误映射测试。

**验收**：Docker + skopeo 路径可用；podman 路径可用；只有 Docker 没有 skopeo 时给出明确安装提示；导入失败不留下半成品镜像；临时文件清理。

**依赖**：T1.12 · **预估**：3h

#### T1.14 `pull` 命令串联与失败回退

**目标**：串联 `resolve -> Manifest -> Blob -> 校验 -> OCI Layout -> 运行时导入`。实现 README 中的失败回退：Git 失败硬错误；Manifest 失败回退本地缓存；CDN 失败按 Blob 重试；导入失败清理临时文件。

**交付**：`src/commands/pull.emo`、对本地 Registry 的集成测试、`--platform` / `--tag` / `--keep-temp` / `--offline` 选项。

**验收**：端到端拉取后 `docker run` 成功；Manifest 网络失败时能用缓存完成（缓存 digest 必须匹配）；Blob 损坏时不导入；导入失败后无临时目录残留；抓包或代理日志确认无 Docker Hub 请求。

**依赖**：T1.9-T1.13 · **预估**：3h

#### T1.15 本地缓存与离线模式

**目标**：统一管理 Git 镜像、Manifest、Blob 缓存；提供 TTL、容量上限、清理与校验命令；支持 `--offline` 只用缓存。

**交付**：`src/cache.emo`、`pokerface cache ls` / `cache rm` / `cache verify`、缓存测试。

**验收**：第二次 pull 在断网时可用；损坏缓存能被识别并淘汰；容量上限生效；`cache rm` 不误删非 pokerface 目录；并发读写安全。

**依赖**：T1.7、T1.14 · **预估**：2-3h

#### T1.16 错误模型、退出码与日志

**目标**：定义稳定的错误分类与退出码，给人看的错误带下一步建议，给脚本的结果可用 `--json` 消费。日志默认简洁，`--verbose` 输出请求 / 命令细节但不泄露 token。

**交付**：`docs/spec/errors.md`、`src/errors.emo`、表驱动测试。

**验收**：用法错误、Git 错误、元数据错误、认证错误、网络错误、完整性错误、运行时错误各有固定退出码；错误输出包含可执行的修复建议；`--verbose` 下 token、Authorization header、预签名 URL 查询串被脱敏。

**依赖**：T1.1 · **预估**：2h

#### T1.17 M1 测试基线、E2E 脚本与规范文档

**目标**：补齐 M1 的测试与文档，让后续改动有回归保护。用本地 fixture Git 仓库 + Emo 写的 mock Registry / CDN 覆盖完整链路。

**交付**：`scripts/e2e-m1.sh`、mock 服务、`docs/spec/` 下的 YAML / lock / config / errors 文档汇总、README 的 M1 使用示例（英文 / 中文同步）。

**验收**：`emo test` 通过；`scripts/e2e-m1.sh` 在干净临时目录可重复运行；不依赖真实 Docker Hub；文档中的命令与实际输出一致。

**依赖**：T1.1-T1.16 · **预估**：2-3h

## 5. M2：分发层 MVP

### 5.1 目标与退出标准

实现 README 中 Distribution Layer 的最小可用形态：OCI 兼容的 Manifest / Tag 管理、Bearer Token 认证、S3/MinIO 对象存储、Blob 预签名 URL 重定向，以及可重复部署的 compose 编排。

退出标准：

- `docker compose up` 能启动 Registry + MinIO + 反向代理，健康检查通过。
- 可用 `oras` / `skopeo` / `pokerface build --push` 推送镜像。
- `GET /v2/<repo>/manifests/<tag>` 返回正确 Manifest，Blob GET 返回 307 到预签名 CDN URL。
- `pokerface resolve` 与 `pokerface pull` 能对这个 Registry 工作。
- pull / push scope 生效，越权请求被拒绝。
- `scripts/e2e-m2.sh` 可在干净环境跑通。

### 5.2 任务总览

| 状态 | ID | 任务 | 依赖 | 预估 |
| --- | --- | --- | --- | --- |
| [ ] | T2.1 | 服务骨架、配置与健康检查 | T1.2 | 2h |
| [ ] | T2.2 | SQLite 数据层与迁移 | T2.1 | 2-3h |
| [ ] | T2.3 | OCI Manifest / Index 模型与校验 | T1.5 | 2-3h |
| [ ] | T2.4 | BlobStore 接口与本地文件后端 | T2.1 | 2h |
| [ ] | T2.5 | AWS SigV4 签名与预签名 URL | T2.1 | 3h |
| [ ] | T2.6 | S3 / MinIO BlobStore 适配 | T2.4、T2.5 | 3h |
| [ ] | T2.7 | `/v2/` 基础协议与错误格式 | T2.1、T2.2 | 1-2h |
| [ ] | T2.8 | Manifest GET / HEAD 与 tag / digest 解析 | T2.2、T2.3、T2.7 | 3h |
| [ ] | T2.9 | Blob GET 与 307 预签名重定向 | T2.4、T2.6、T2.8 | 2-3h |
| [ ] | T2.10 | Blob 上传：POST / PUT | T2.4、T2.7 | 3h |
| [ ] | T2.11 | 分块上传与断点续传：PATCH / GET / DELETE | T2.10 | 3h |
| [ ] | T2.12 | Manifest PUT 与 tag 更新 | T2.3、T2.10、T2.11 | 2-3h |
| [ ] | T2.13 | 解析 / 元数据 API | T2.8、T2.12 | 2h |
| [ ] | T2.14 | 认证与 Token 服务 | T2.7 | 3-4h |
| [ ] | T2.15 | 缓存头、ETag 与 CDN 行为 | T2.8、T2.9 | 2h |
| [ ] | T2.16 | Tag 列表与分页 | T2.12 | 2h |
| [ ] | T2.17 | 部署编排：Registry + MinIO + Caddy | T2.6、T2.14 | 3h |
| [ ] | T2.18 | 可观测性与审计 | T2.1 | 2-3h |
| [ ] | T2.19 | 协议冒烟与一致性测试 | T2.1-T2.18 | 3h |

### 5.3 任务详情

#### T2.1 服务骨架、配置与健康检查

**目标**：建立 Registry 服务入口，使用 `httpd` 注册路由，支持 YAML + 环境变量配置、`/healthz`、`/readyz`、优雅停机与请求大小限制。

**交付**：`registry/main.emo`、配置结构体与校验、健康检查、`docs/spec/registry-config.md`。

**验收**：`emo build` 通过；`/healthz` 返回 200；数据库或对象存储不可用时 `/readyz` 返回非 200；收到 SIGTERM 后停止接收新请求并完成在途请求；配置缺失时有明确错误。

**依赖**：T1.2 · **预估**：2h

#### T2.2 SQLite 数据层与迁移

**目标**：用 SQLite 保存仓库、Manifest、Tag、Blob、上传会话等元数据；建立可重复执行的迁移机制。

**交付**：`registry/db.emo`、迁移 SQL、`schema_version` 表、CRUD 测试。

**验收**：空库初始化成功；重复迁移幂等；`repositories` / `manifests` / `tags` / `blobs` / `uploads` 的约束正确；WAL 与 busy timeout 配置生效；并发读不报错。

建议表：

- `repositories(id, name UNIQUE, created_at)`
- `manifests(id, repository_id, digest, media_type, size, body, created_at)`
- `tags(repository_id, tag, digest, updated_at)`
- `blobs(repository_id, digest, size, created_at)`
- `uploads(id, repository_id, state, created_at, expires_at)`

**依赖**：T2.1 · **预估**：2-3h

#### T2.3 OCI Manifest / Index 模型与校验

**目标**：实现 OCI Image Manifest、Image Index、Image Config 的解析与编码；校验 descriptor 的 media type、digest、size；支持按平台选择子 Manifest。

**交付**：`registry/oci.emo`、golden fixtures、解析 / 校验测试。

**验收**：真实镜像的 Manifest 可解析；缺字段 / digest 格式错误 / size 不匹配被拒绝；编码后的字节可复现；Index 的平台选择与客户端一致。

**依赖**：T1.5 · **预估**：2-3h

#### T2.4 BlobStore 接口与本地文件后端

**目标**：定义 Blob 存储抽象：`put`、`get`、`head`、`delete`、`presign_get`。本地文件后端用于开发和测试，路径以 digest 内容寻址。

**交付**：`registry/blobstore.emo`、本地后端、接口测试。

**验收**：写入采用临时文件 + 原子 rename；读取支持 Range；路径不穿越出根目录；重启后数据仍在；`presign_get` 在不支持预签名的后端返回空值，由上层回退到直接流式返回。

**依赖**：T2.1 · **预估**：2h

#### T2.5 AWS SigV4 签名与预签名 URL

**目标**：用 `crypto` 的 HMAC-SHA256 实现 AWS Signature V4 的请求签名与查询串预签名，兼容 MinIO 的 path-style 访问。

**交付**：`registry/sigv4.emo`、官方测试向量、固定时间源的单元测试。

**验收**：签名结果与 AWS 测试向量一致；预签名 URL 在有效期内可访问、过期后拒绝；URI 编码符合 SigV4 要求；密钥与签名不出现在日志中。

**依赖**：T2.1 · **预估**：3h

#### T2.6 S3 / MinIO BlobStore 适配

**目标**：基于 SigV4 实现 S3 兼容存储后端，支持 PUT / GET / HEAD / DELETE 与 GET 预签名；配置 endpoint、bucket、region、access key、secret key、TLS、path-style。

**交付**：`registry/s3_blobstore.emo`、MinIO 集成测试、配置示例。

**验收**：对 MinIO 完成上传 / 下载 / 预签名访问；bucket 不存在时启动失败并提示；TLS 与自签 CA 可配置；网络错误有重试与清晰错误；不在日志中输出密钥。

**依赖**：T2.4、T2.5 · **预估**：3h

#### T2.7 `/v2/` 基础协议与错误格式

**目标**：实现 `GET /v2/`，返回 `Docker-Distribution-API-Version: registry/2.0`；统一 OCI 错误 JSON：`{"errors":[{"code","message","detail"}]}`；补全 401 / 404 / 405 的响应。

**交付**：路由与中间件、错误响应辅助函数、协议测试。

**验收**：无认证模式 `GET /v2/` 返回 200；开启认证后由 T2.14 覆盖 401 挑战；未知路由返回 404；方法不匹配返回 405 并带 `Allow`；所有错误响应符合 OCI 错误格式；响应带 request id。

**依赖**：T2.1、T2.2 · **预估**：1-2h

#### T2.8 Manifest GET / HEAD 与 tag / digest 解析

**目标**：实现 `/v2/<name>/manifests/<reference>`，其中 `<name>` 可含 `/`；reference 支持 tag 与 digest；处理 `Accept`，返回原始 Manifest 字节与 `Docker-Content-Digest`、`Content-Type`、`Content-Length`。

**交付**：路由、查询逻辑、HEAD 支持、测试。

**验收**：按 tag 与 digest 均可取；不存在返回 404 `MANIFEST_UNKNOWN`；HEAD 不返回 body；digest 不匹配时拒绝；多架构 Index 可正常返回。

**依赖**：T2.2、T2.3、T2.7 · **预估**：3h

#### T2.9 Blob GET 与 307 预签名重定向

**目标**：实现 `/v2/<name>/blobs/<digest>`。使用 S3 时返回 307 + `Location` 预签名 URL；使用本地文件后端时直接流式返回 200。HEAD 返回元数据，不重定向。

**交付**：Blob GET / HEAD、预签名 TTL 配置、测试。

**验收**：307 的 Location 可直接下载且过期失效；本地后端返回正确 `Content-Length` 与 `Docker-Content-Digest`；不存在返回 404 `BLOB_UNKNOWN`；客户端可通过两种模式完成下载。

**依赖**：T2.4、T2.6、T2.8 · **预估**：2-3h

#### T2.10 Blob 上传：POST / PUT

**目标**：实现最小 OCI 上传流程：`POST /v2/<name>/blobs/uploads/` 创建会话，`PUT ...?digest=sha256:...` 上传完整 Blob；校验 digest 与 size，去重，清理过期会话。

**交付**：上传路由、会话表、单块上传测试、`curl` 示例。

**验收**：上传成功后 `HEAD` 可见；digest 不匹配返回 400 且不落盘；重复 Blob 不重复存储；过期会话可清理；上传大小限制生效。

**依赖**：T2.4、T2.7 · **预估**：3h

#### T2.11 分块上传与断点续传：PATCH / GET / DELETE

**目标**：补齐 OCI 分块上传：`PATCH` 追加数据、`GET` 查询偏移、`DELETE` 取消会话；支持客户端断点续传。

**交付**：分块上传实现、状态机测试、与 `oras` / `skopeo` 的兼容测试。

**验收**：多段 PATCH 后 PUT 成功；中途 GET 返回正确 `Range`；DELETE 后会话不可用；并发写同一会话被拒绝；异常中断的会话可过期清理。

**依赖**：T2.10 · **预估**：3h

#### T2.12 Manifest PUT 与 tag 更新

**目标**：实现 `PUT /v2/<name>/manifests/<tag|digest>`，校验 Manifest 中引用的 config / layers 均已存在，写入 Manifest 并原子更新 tag。

**交付**：Manifest 写入、tag 更新、事务测试。

**验收**：`oras push` / `skopeo copy` 可推送成功；引用缺失返回 `MANIFEST_BLOB_UNKNOWN`；tag 更新是原子的；返回 `Docker-Content-Digest`；失败时旧 tag 不被覆盖。

**依赖**：T2.3、T2.10、T2.11 · **预估**：2-3h

#### T2.13 解析 / 元数据 API

**目标**：提供便于 CLI 和运维排查的只读接口：`GET /api/v1/resolve?repository=<name>&tag=<tag>`，返回 digest、media type、平台与可选的 commit 注解（来自 `org.opencontainers.image.revision`）。

**交付**：接口、JSON 响应、认证与测试。

**验收**：tag 存在时返回完整信息；不存在返回 404；无权限返回 401/403；不泄露存储凭据；`pokerface` 可用它作为 Git 元数据缺失时的只读兜底。

**依赖**：T2.8、T2.12 · **预估**：2h

#### T2.14 认证与 Token 服务

**目标**：实现 Bearer Token 流程：`GET /v2/` 返回 401 与 `WWW-Authenticate`；`/token` 支持 Basic 认证换取带 scope 的短时 Token；中间件校验 `repository:<name>:pull|push`。

**交付**：Token 签发 / 校验、scope 中间件、配置示例、负向测试。

**验收**：匿名 pull 被拒绝（若开启认证）；只有 pull scope 不能 push；token 过期后 401；跨仓库访问被拒绝；密码与签名密钥不出现在日志；v0.1 配置文件方式可用。

**依赖**：T2.7 · **预估**：3-4h

#### T2.15 缓存头、ETag 与 CDN 行为

**目标**：为不可变 Blob 与可变 Manifest 设置不同的缓存策略；支持 `ETag` / `If-None-Match`；保证 CDN 可缓存 Blob，而 tag 更新能及时生效。

**交付**：响应头中间件、CDN 配置说明、测试。

**验收**：Blob 返回长缓存 + `immutable`；Manifest 返回短缓存或 `no-cache`；`If-None-Match` 命中返回 304；tag 更新后新请求能看到新 digest；不因 CDN 缓存导致旧 Manifest 长期不更新。

**依赖**：T2.8、T2.9 · **预估**：2h

#### T2.16 Tag 列表与分页

**目标**：实现 `GET /v2/<name>/tags/list`，按字典序返回 tag，支持 `n` 与 `last` 分页，并在有下一页时返回 `Link` 头。

**交付**：路由、分页逻辑、测试。

**验收**：空仓库返回空列表；分页边界正确；`last` 不存在时从合理位置开始；需要 pull 权限；响应符合 OCI 规范。

**依赖**：T2.12 · **预估**：2h

#### T2.17 部署编排：Registry + MinIO + Caddy

**目标**：提供可重复部署：多阶段构建 Emo 二进制，运行镜像包含必要动态库；Compose 启动 Registry、MinIO、Caddy；配置卷、健康检查、TLS 与 `.env.example`。

**交付**：`deploy/Dockerfile`、`deploy/compose.yaml`、`deploy/Caddyfile`、`.env.example`、部署文档。

**验收**：干净机器上 `docker compose up -d` 后三个服务健康；Registry 通过 Caddy 访问；MinIO 数据持久化；重启后数据不丢；`.env.example` 不含真实密钥。

**依赖**：T2.6、T2.14 · **预估**：3h

#### T2.18 可观测性与审计

**目标**：补充结构化日志（`slog` JSON）、request id、访问日志、认证审计与 Prometheus 文本指标；避免记录 token、Authorization、预签名查询串。

**交付**：日志中间件、`/metrics`、审计事件、测试。

**验收**：每请求有 request id；日志可被 `jq` 解析；指标包含请求数、延迟、错误数、上传 / 下载字节数；认证失败有审计记录；敏感字段被脱敏。

**依赖**：T2.1 · **预估**：2-3h

#### T2.19 协议冒烟与一致性测试

**目标**：用真实客户端验证 Registry：`oras` 或 `skopeo` 推送、`pokerface pull` 拉取、预签名 Blob 下载、认证负向用例；形成可重复的冒烟脚本。

**交付**：`scripts/e2e-m2.sh`、测试镜像 fixture、测试说明。

**验收**：脚本从干净环境启动 compose、完成 push / pull / 校验并清理；失败时输出可定位的日志；不访问 Docker Hub；覆盖 401、404、digest 不匹配等错误路径。

**依赖**：T2.1-T2.18 · **预估**：3h

## 6. M4：构建、CI 与交付

### 6.1 目标与退出标准

补齐构建侧与交付物：`pokerface build`、镜像推送、lock 写回、CI 模板、安装脚本、文档站、示例应用与端到端演示。

退出标准：

- 示例仓库可通过 `pokerface build --push` 完成构建、推送并写回 `pokerface.lock.yaml`。
- GitHub Actions 模板可复用，且不会触发无限提交循环。
- 文档站覆盖安装、快速开始、CLI、配置、协议与运维。
- `scripts/e2e.sh` 在干净环境完成 `build -> push -> resolve -> pull -> run`。
- README（英文与中文）与实际状态一致。

### 6.2 任务总览

| 状态 | ID | 任务 | 依赖 | 预估 |
| --- | --- | --- | --- | --- |
| [ ] | T4.1 | `pokerface build` 命令与构建计划 | T1.4、T1.5 | 2h |
| [ ] | T4.2 | BuildKit / podman 构建适配 | T4.1 | 3-4h |
| [ ] | T4.3 | Registry 推送：Blob + Manifest | T1.10、T2.12、T4.2 | 3h |
| [ ] | T4.4 | lock 文件生成与写回 | T4.3 | 2h |
| [ ] | T4.5 | 构建触发与版本策略 ADR | 无 | 1h |
| [ ] | T4.6 | CI 模板：GitHub Actions 为主 | T4.3、T4.4 | 3h |
| [ ] | T4.7 | 安装脚本与发布工作流 | T1.1 | 3h |
| [ ] | T4.8 | 文档站骨架与导航 | T4.5 | 2-3h |
| [ ] | T4.9 | 快速开始与安装文档 | T4.7、T4.8 | 2h |
| [ ] | T4.10 | CLI 与配置参考 | T1.1、T1.8 | 2h |
| [ ] | T4.11 | YAML / lock / 元数据规范 | T1.4、T1.5 | 3h |
| [ ] | T4.12 | Registry 运维指南 | T2.17 | 3h |
| [ ] | T4.13 | 示例应用 | T4.2、T4.3 | 3h |
| [ ] | T4.14 | 端到端演示脚本 | T4.3、T4.13、T1.14 | 3h |
| [ ] | T4.15 | 故障回退与排障矩阵 | T1.14、T2.19 | 2h |
| [ ] | T4.16 | README、中文版与发布清单 | T4.8-T4.15 | 2h |
| [ ] | T4.17 | CI 端到端回归 | T4.14 | 3h |

### 6.3 任务详情

#### T4.1 `pokerface build` 命令与构建计划

**目标**：读取 `pokerface.yaml`，校验配置与上下文，解析 tag 模板，生成构建计划并以 `--dry-run` 展示：镜像名、tag 列表、平台、构建参数、Dockerfile、上下文。

**交付**：`src/commands/build.emo`、tag 渲染器、dry-run 测试。

**验收**：示例配置输出稳定；缺 Dockerfile / 上下文不存在 / tag 重复时报错；`--dry-run` 不执行任何构建或网络请求；支持 `--platform` 覆盖。

**依赖**：T1.4、T1.5 · **预估**：2h

#### T4.2 BuildKit / podman 构建适配

**目标**：封装本地构建工具。优先 Docker BuildKit `buildx build --output type=oci`；podman 作为备选。写入 OCI 标准标签：`org.opencontainers.image.revision`、`source`、`version`、`created`。

**交付**：`src/build.emo`、工具检测、日志流式输出、构建测试。

**验收**：示例 Dockerfile 可构建为 OCI Layout；镜像 inspect 能看到 commit / source 标签；构建失败返回原始日志与退出码；无 BuildKit 时给出清晰提示；多平台构建作为可选能力，失败不影响单平台。

**依赖**：T4.1 · **预估**：3-4h

#### T4.3 Registry 推送：Blob + Manifest

**目标**：复用 M1 的 Registry 客户端，实现 Blob 上传（单块 / 分块）、Manifest 推送、tag 更新、digest 捕获与重试。

**交付**：`src/push.emo`、推送测试、进度输出。

**验收**：推送到 M2 Registry 成功；返回的 digest 与本地一致；重复推送可跳过已存在 Blob；中途失败可重试且不破坏已有 tag；认证 scope 正确。

**依赖**：T1.10、T2.12、T4.2 · **预估**：3h

#### T4.4 lock 文件生成与写回

**目标**：构建推送成功后生成 `pokerface.lock.yaml`，记录 commit、镜像、tags、digest、平台、builder；支持 `--write-lock`，可选 `--commit` 只做本地 Git 提交，不自动 push。

**交付**：lock 生成器、合并逻辑、测试。

**验收**：重复构建同一镜像时 lock 幂等；多 tag、多平台条目稳定排序；不覆盖无关条目；不写入真实密钥；`pokerface resolve` 能直接消费生成的 lock。

**依赖**：T4.3 · **预估**：2h

#### T4.5 构建触发与版本策略 ADR

**目标**：明确 v0.1 的构建触发方式：由 Git push / tag / CI `workflow_dispatch` 触发，不实现自建 webhook 服务；定义 tag 规则（默认分支 `latest`、Git tag 原样、commit 短 SHA、语义化版本）。

**交付**：`docs/adr/0001-build-trigger.md`、版本策略文档。

**验收**：决策记录包含背景、备选方案与取舍；CI 模板与 tag 规则一致；文档明确“轮询 / 自建 webhook”留到后续版本。

**依赖**：无 · **预估**：1h

#### T4.6 CI 模板：GitHub Actions 为主

**目标**：提供可复用 workflow：checkout、安装 pokerface、登录 Registry、`pokerface build --push --write-lock`、提交 lock 回仓库。补充 GitLab CI / Gitea Actions 的最小示例。

**交付**：`.github/workflows/publish.yaml`、`docs/ci/github-actions.md`、GitLab / Gitea 示例。

**验收**：workflow 通过 `actionlint`；示例仓库能跑通；提交 lock 使用 `[skip ci]` 或路径过滤避免循环；secrets 不落盘；权限最小化。

**依赖**：T4.3、T4.4 · **预估**：3h

#### T4.7 安装脚本与发布工作流

**目标**：提供 `install.sh` 与发布流程：识别 OS / 架构、下载对应二进制、校验 checksum、安装到 `PATH`；发布 workflow 交叉编译 Linux / macOS 的 amd64 / arm64 产物。

**交付**：`install.sh`、`.github/workflows/release.yaml`、checksum 文件、安装文档。

**验收**：干净容器中 `curl ... | sh` 安装成功；`pokerface version` 与发布版本一致；checksum 不匹配时拒绝安装；脚本不使用不安全的临时文件权限。

**依赖**：T1.1 · **预估**：3h

#### T4.8 文档站骨架与导航

**目标**：建立文档站：Getting Started、CLI、Configuration、Spec、Registry、Examples、Troubleshooting。优先纯 Markdown + GitHub Pages；需要搜索时再引入 VitePress。

**交付**：`docs-site/` 或 `docs/` 站点配置、导航、首页、部署 workflow。

**验收**：本地可预览；导航无死链；移动端可读；部署到 GitHub Pages 成功；文档源文件仍在 `docs/` 便于 review。

**依赖**：T4.5 · **预估**：2-3h

#### T4.9 快速开始与安装文档

**目标**：让新用户在 10 分钟内完成：安装、`pokerface resolve`、`pokerface pull`、`docker run`。明确前置依赖：Git、skopeo、Docker / podman。

**交付**：`docs/getting-started.md`、可复制命令、预期输出、常见失败提示。

**验收**：按文档在干净环境执行成功；命令与当前 CLI 一致；中文版关键段落同步；明确说明不依赖 Docker Hub。

**依赖**：T4.7、T4.8 · **预估**：2h

#### T4.10 CLI 与配置参考

**目标**：为所有命令、参数、环境变量、配置文件字段、退出码建立参考文档，并尽量从 `--help` 输出生成或校验。

**交付**：`docs/reference/cli.md`、`docs/reference/config.md`、帮助文本快照测试。

**验收**：文档覆盖所有命令；参数默认值准确；退出码与 `docs/spec/errors.md` 一致；CI 检查帮助文本变更时提醒更新文档。

**依赖**：T1.1、T1.8 · **预估**：2h

#### T4.11 YAML / lock / 元数据规范

**目标**：把 `pokerface.yaml`、`pokerface.lock.yaml` 与 Manifest 元数据整理成正式规范：字段、类型、校验规则、版本兼容策略、示例、与 OCI 字段的映射。

**交付**：`docs/spec/pokerface-yaml.md`、`docs/spec/pokerface-lock.md`、JSON Schema（可选但推荐）、示例。

**验收**：所有示例通过 Schema 校验；规范覆盖未知字段 / 版本升级策略；与实现中的校验一致；review 无歧义。

**依赖**：T1.4、T1.5 · **预估**：3h

#### T4.12 Registry 运维指南

**目标**：面向自建 Registry 的运维者：Compose 部署、S3/MinIO 配置、CDN 接入、TLS、认证、备份、Blob 清理、容量与监控、安全清单。

**交付**：`docs/registry/operations.md`、部署示例、故障排查清单。

**验收**：按文档可从零部署；CDN 缓存策略与代码一致；备份 / 恢复步骤可执行；包含“不要暴露 MinIO 凭据”的安全提醒。

**依赖**：T2.17 · **预估**：3h

#### T4.13 示例应用

**目标**：提供一个最小示例：Dockerfile + `pokerface.yaml` + 一个可访问的 HTTP 服务；用于演示 Git 元数据、构建、推送与拉取。

**交付**：`examples/hello/`、示例 README、预期镜像大小与启动命令。

**验收**：`pokerface build --push --write-lock` 成功；`pokerface pull` 后容器返回 200；镜像不含构建缓存与密钥；示例可作为 CI 模板的输入。

**依赖**：T4.2、T4.3 · **预估**：3h

#### T4.14 端到端演示脚本

**目标**：一条命令演示完整链路：启动本地 Registry / MinIO、构建示例、推送、写 lock、`resolve`、`pull`、运行容器并断言 HTTP 响应。

**交付**：`scripts/e2e.sh`、`--ci` 模式、日志与清理逻辑。

**验收**：干净机器上一条命令成功；失败时保留诊断日志；不访问 Docker Hub；耗时在可接受范围（目标 10 分钟内）；重复执行不污染环境。

**依赖**：T4.3、T4.13、T1.14 · **预估**：3h

#### T4.15 故障回退与排障矩阵

**目标**：把 README 中的失败回退写成可执行文档，并逐项验证：Git 失败、Manifest 失败、CDN 失败、digest 不匹配、运行时导入失败、缓存损坏。

**交付**：`docs/troubleshooting.md`、回退矩阵、诊断命令、测试记录。

**验收**：每个场景都有“现象 / 原因 / 处理 / 验证”四段；文档行为与实现一致；包含离线模式与缓存清理步骤。

**依赖**：T1.14、T2.19 · **预估**：2h

#### T4.16 README、中文版与发布清单

**目标**：更新 README 的项目状态、Quick Start、Roadmap 勾选与链接；同步 `README.zh-CN.md`；建立发布清单（版本号、changelog、tag、安装脚本、回滚）。

**交付**：更新后的 `README.md` / `README.zh-CN.md`、`RELEASE.md`、`CHANGELOG.md`。

**验收**：英文与中文内容一一对应；命令可复制执行；Roadmap 勾选与实际一致；发布清单覆盖版本号与 tag 规则；无过期截图或链接。

**依赖**：T4.8-T4.15 · **预估**：2h

#### T4.17 CI 端到端回归

**目标**：在 CI 中定期运行端到端链路，防止 Registry / CLI / 构建脚本的回归。支持手动触发与每日定时。

**交付**：`.github/workflows/e2e.yaml`、缓存策略、失败日志 artifact。

**验收**：CI 在主干通过；耗时控制在 15 分钟内；失败时能下载 compose 日志与 CLI 日志；E2E 运行阶段不访问 Docker Hub；构建所需基础镜像提前缓存或使用本地镜像，并在 workflow 中固定来源。

**依赖**：T4.14 · **预估**：3h

## 7. 建议执行顺序

单人开发建议按下面的顺序推进；标“可并行”的任务可以在等 CI 或等 review 时穿插。

1. **契约阶段**：T1.1 -> T1.2 -> T1.3 -> T1.4 -> T1.5。先把 CLI、引用语法、两份 YAML 规范冻结。
2. **客户端解析闭环**：T1.6 -> T1.7 -> T1.8 -> T1.9 -> T1.16。此时 `resolve` 已可用。
3. **客户端拉取闭环**：T1.10 -> T1.11 -> T1.12 -> T1.13 -> T1.14 -> T1.15 -> T1.17。
4. **服务端 MVP**：T2.1 -> T2.2 -> T2.3 -> T2.4 -> T2.5 -> T2.6 -> T2.7 -> T2.8 -> T2.9 -> T2.10 -> T2.11 -> T2.12 -> T2.14 -> T2.13 -> T2.15 -> T2.16 -> T2.18 -> T2.17 -> T2.19。
5. **构建与交付**：T4.1 -> T4.2 -> T4.3 -> T4.4 -> T4.5 -> T4.6 -> T4.7。
6. **文档与端到端**：T4.8 -> T4.9 -> T4.10 -> T4.11 -> T4.12 -> T4.13 -> T4.14 -> T4.15 -> T4.16 -> T4.17。

可并行项：

- T1.4 / T1.5 定稿后，M2 的 T2.2 / T2.3 可以提前做。
- T4.5 / T4.8 / T4.10 / T4.11 可以在 M2 开发期间穿插。
- T1.15 的缓存与 T1.16 的错误模型不阻塞主链路，可放在等待构建或 review 的碎片时间。

关键路径：`T1.2 -> T1.5 -> T1.10 -> T1.13 -> T1.14 -> T2.17 -> T4.3 -> T4.14`。

## 8. 风险与待验证项

| 风险 | 影响 | 缓解 |
| --- | --- | --- |
| Emo `http` 客户端不跟随重定向，且响应体整体读入内存 | 大镜像层下载可能占用大量内存，307 需要手动处理 | T1.2 先验证；必要时在 T1.11 基于 `net` 实现流式下载与重定向跟随 |
| S3 SigV4 实现细节多 | 预签名 URL 不通，阻塞 Blob 拉取 | T2.5 用官方测试向量；先用 MinIO 做集成；保留“本地文件后端 + 直接流式返回”作为开发模式 |
| `skopeo` 不是所有环境都有 | `pull` 无法导入 Docker | T1.13 做工具检测与清晰提示；文档列出安装方式；后续版本再考虑内置导入 |
| OCI 客户端兼容性不足 | `oras` / `skopeo` 推送失败 | T2.19 用真实客户端做冒烟；按错误逐项补齐，不追求一次性完整规范 |
| CDN 缓存导致 tag 更新不可见 | 拉取到旧 Manifest | T2.15 使用短缓存 / `no-cache` + ETag；Blob 才使用长缓存 |
| Git 仓库很大或服务器限制 fetch | `resolve` 慢或失败 | 使用 bare 缓存 + 浅 fetch；优先只取 lock 文件；缓存 TTL 可配置 |
| 代理 / 网络环境干扰 | 请求被劫持或超时 | 全程使用自有域名；日志记录实际请求域名；E2E 断言不访问 Docker Hub |
| 多架构镜像复杂度 | 构建与拉取平台选择出错 | v0.1 先保证单平台；T1.10 解析 Index，T4.2 多平台作为可选能力 |

## 9. MVP 验收清单

- [ ] `pokerface resolve` 能输出 `tag -> commit -> digest`。
- [ ] `pokerface pull` 能完成下载、校验、导入，`docker run` / `podman run` 正常。
- [ ] 拉取过程不访问 `registry-1.docker.io`。
- [ ] Registry 可通过 compose 一键启动，MinIO 数据持久化。
- [ ] Manifest / Blob / Tag 的 OCI 必要接口可用，`oras` 或 `skopeo` 冒烟通过。
- [ ] Blob 通过预签名 URL 下载，过期后失效。
- [ ] pull / push scope 生效，越权请求被拒绝。
- [ ] `pokerface build --push --write-lock` 可完成构建、推送与元数据写回。
- [ ] CI 模板可用，且不会产生提交循环。
- [ ] 示例应用可通过 `scripts/e2e.sh` 一键演示。
- [ ] 文档站包含安装、快速开始、CLI、规范、Registry 运维与排障。
- [ ] README 英文与中文版本同步，Roadmap 与实际状态一致。
