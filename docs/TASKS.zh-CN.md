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
| [x] | T1.12 | OCI 镜像布局组装 | T1.10、T1.11 | 2-3h |
| [x] | T1.13 | 运行时导入适配 | T1.12 | 3h |
| [x] | T1.14 | `pull` 命令串联与失败回退 | T1.9-T1.13 | 3h |
| [x] | T1.15 | 本地缓存与离线模式 | T1.7、T1.14 | 2-3h |
| [x] | T1.16 | 错误模型、退出码与日志 | T1.1 | 2h |
| [x] | T1.17 | M1 测试基线、E2E 脚本与规范文档 | T1.1-T1.16 | 2-3h |

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

> **备注**（2026-11-18，约 2h）：完成。`src/oci.emo` 把已下载的 Manifest、config、layer 字节组装为标准 OCI Layout：`oci-layout`、带 `org.opencontainers.image.ref.name` tag 注解的 `index.json`、以及 `blobs/sha256/<hex>`。组装遵循“先校验后写入”：Manifest 字节先与外部声明的 digest 比对；每个 config/layer descriptor 在写盘前必须配到 `BlobSource`（缺少来源、声明大小不一致、多出未被引用的来源都会明确报错）；拷贝时边流式写入 `<dest>.part` 边计算 SHA-256 和字节数，digest+size 都匹配后才 rename；`index.json` 最后写入——磁盘上的布局永远不会引用损坏或缺失的 Blob。已存在且一致的 Blob 直接复用，重复组装是幂等的。`validate(dir)` 完全从磁盘重新校验（布局版本、index descriptor、Manifest 的 config/layers、嵌套 index），并报告去重后的 Blob/字节数；缺失、损坏、大小不符都会点名引用它的 descriptor。`new_temp_layout(keep)` + `TempLayout.cleanup()` 提供 `--keep` 语义，T1.14 会把它接到命令行选项上，导入失败后可以保留现场排查。Fixture：`test/fixtures/oci/` 是一个真正合法的单层镜像（gzip tar + `diff_ids` 匹配的 config），`skopeo inspect oci:<dir>:latest` 可直接读取并返回 Manifest digest——已用 skopeo 1.25 手工验证。测试：`test/oci_layout.emo` 共 15 个（解析错误、组装/校验、幂等、Manifest digest 不符、来源缺失/损坏/多余、validate 捕获缺失与损坏 Blob 及错误布局版本、临时目录 keep/cleanup、以及 skopeo 退出码 127 时跳过的真实调用）。文档：`docs/spec/oci-layout.md`。踩坑：Emo 里 `;` 不是语句分隔符（`E2025`），多条语句要换行；`json.object`/`json.array` 工厂接收显式的元组/数组字面量；`file.read` 是字节安全的，gzip fixture 可作为 String 原样往返；digest 形状校验复用了 `src.blob.digest_hex`。

#### T1.13 运行时导入适配

**目标**：把 OCI Layout 导入本地运行时。优先 `skopeo copy oci:<dir> docker-daemon:<image>:<tag>`；podman 使用 `containers-storage:`；containerd 使用 `oci-archive` + `ctr images import`。检测可用工具并给出清晰提示。

**交付**：`src/runtime.emo`、支持矩阵文档、命令构造与错误映射测试。

**验收**：Docker + skopeo 路径可用；podman 路径可用；只有 Docker 没有 skopeo 时给出明确安装提示；导入失败不留下半成品镜像；临时文件清理。

**依赖**：T1.12 · **预估**：3h

> **备注**（2026-11-18，约 2.5h）：完成。`src/runtime.emo` 把检测、规划、执行拆开，命令无需真实运行时也能构造和测试：`detect` 用 `docker/podman/skopeo/ctr --version` 探测；`select_runtime` 尊重显式选择（`ctr` 作为 containerd 别名），自动模式按 docker > podman > containerd；`plan` 产出精确 argv。Docker 走 `skopeo copy oci:<dir>:<tag> docker-daemon:<image>:<tag>`，podman 走 `containers-storage:<image>:<tag>`，containerd 先用 skopeo 生成 `<layout>.oci-archive.tar` 再执行 `ctr images import --base-name <image> <archive>`（完整引用不能写进归档的 `ref.name`：skopeo 按最后一个冒号切分 `oci-archive:path:tag`）。所有路径都依赖 skopeo，缺失时在规划阶段就给出 brew/apt/dnf 安装提示。`execute` 先记录目标 tag 是否已存在，执行导入后用 `docker/podman image inspect` 或 `ctr images ls --quiet` 精确行匹配校验；失败时删除归档，并且**仅当 tag 原本不存在**时才删除可能残留的 tag，已有镜像绝不受影响。错误按 runner 输出映射（退出码 127、daemon 不可达、权限不足），并剥掉共享 runner 的 `git:` 前缀。测试：`test/runtime_import.emo` 共 20 个（检测、三种规划、自动/显式选择、无运行时/未知运行时/未安装、skopeo 提示、非法请求、Docker 成功与失败路径含校验失败和保留已有镜像、权限与 127 映射、containerd 归档成功/失败清理、keep、prepare）。**已用真实 Docker daemon（29.9.3）与 skopeo 1.25.2 手工端到端验证**：fixture 布局成功导入为 `pokerface-t113-check:latest`，`docker image inspect` 通过，随后删除了测试镜像。本机未安装 podman 与 `ctr`，这两条路径仅由命令构造/错误映射测试覆盖。文档：`docs/spec/runtime-import.md`（支持矩阵）。踩坑：共享 runner 即使运行非 git 工具也会返回 `git: '<tool>' exited …`；FakeRunner 路由表是有序的，同一前缀的重复探测（导入前后 inspect）用 `times` 次数表达；`os` 没有 `stat`，测试里用 `file.read` 判断归档是否存在。

#### T1.14 `pull` 命令串联与失败回退

**目标**：串联 `resolve -> Manifest -> Blob -> 校验 -> OCI Layout -> 运行时导入`。实现 README 中的失败回退：Git 失败硬错误；Manifest 失败回退本地缓存；CDN 失败按 Blob 重试；导入失败清理临时文件。

**交付**：`src/commands/pull.emo`、对本地 Registry 的集成测试、`--platform` / `--tag` / `--keep-temp` / `--offline` 选项。

**验收**：端到端拉取后 `docker run` 成功；Manifest 网络失败时能用缓存完成（缓存 digest 必须匹配）；Blob 损坏时不导入；导入失败后无临时目录残留；抓包或代理日志确认无 Docker Hub 请求。

**依赖**：T1.9-T1.13 · **预估**：3h

> **备注**（2026-11-18，约 3h）：完成。`src/commands/pull.emo` 串联 Git 解析 → Manifest → Blob → OCI Layout → 运行时导入，并落实 README 的失败回退。**Manifest**：锁里 `manifest_digest` 对应 `platforms` 第一个平台时直接按它拉取；其他平台用锁里的 `digest`（多平台时是 index），交给 T1.10 按平台选子 Manifest；每次拉取都校验 body 与请求 digest 一致、最终 Manifest 与锁一致。网络/5xx 失败时回退到按 `(image, reference, platform)` 缓存的 Manifest，缓存 digest 必须与锁匹配，并在 stderr 警告原始错误。**Blob**：`<cache_root>/blobs/sha256` 内容寻址缓存，每次使用都校验；T1.11 的重试、Range 续传、digest 校验照常生效；在线时会重新下载损坏的缓存条目，离线时明确报错。**鉴权**：新增 `src.blob.RegistryBlobTransport`，Bearer token 只发第一跳，307 到预签名 CDN URL 时不会带上。**清理**：临时布局（T1.12）在成功和所有失败路径都会删除；T1.13 清理归档和可能残留的 tag；`--keep-temp` 保留布局（与归档）并打印/附加路径。**离线**（`--offline`）要求完整 commit SHA，锁从镜像缓存里用纯 `git show` 读取（绝不 fetch），Manifest/Blob 只用缓存。`run_with` 把运行时 runner 作为注入点，`run` 用真实 runner。选项：`--platform`、`--tag`、`--keep-temp`、`--offline`；`--json` 输出 image/digest/commit/platform/runtime/runtime_ref/manifest_cached/blob 计数。文档：`docs/spec/pull.md`、`docs/cli.md`。测试：`test/pull_cmd.emo` 共 15 个——真实本地 httpd 注册表上的完整流水线（校验 token 的 manifest/blob、307 到拒绝 Authorization 的 CDN 端点、digest 头）、Manifest 失败回退缓存、离线冷/热缓存、缓存损坏时在线修复与离线拒绝、导入失败的有/无 `--keep-temp`、index 平台选择与 miss、tag/platform/参数/镜像拆分辅助函数，以及本地 Git 仓库 + 假运行时的完整命令；`emo test` 174/174。完整命令测试首跑失败：它只把 registry token 传给了 `pull_image` 的 deps，而 `run_with` 是从 settings 读取——现已让假 env 设置 `POKERFACE_REGISTRY_TOKEN`。**已手工端到端验证**：构建一个可运行的 linux/arm64 镜像（`ubuntu:24.04` + `/bin/echo`），用 skopeo 导出为 OCI Layout，由本地 Go 注册表 fixture（307 Blob 重定向）提供，真实 `pull.run_with` 配真实 Docker/skopeo 运行时执行——30,797,821 字节的 layer 完成下载、校验、组装并导入——随后 `docker run` 输出 `pokerface pull ok`；再用真实 CLI 带 `--offline` 和完整 commit SHA 二次拉取（注册表已停止），Git 镜像、缓存 Manifest 与缓存 Blob 全部复用并成功重新导入；所有测试镜像均已删除。踩坑：Emo 的 `httpd` fixture 无法承载 NUL 字节，所以集成测试的 layer 体是纯 ASCII（真实 gzip 层由手工 E2E 覆盖）；标准库 `http` 客户端确实能访问进程内 `httpd`；离线 Git 路径不能调 `git_cache.load_lock`（会触发 fetch），所以新增 `load_lock_offline`；`--keep-temp` 同时控制 T1.12 的布局保留与 T1.13 的归档保留。

#### T1.15 本地缓存与离线模式

**目标**：统一管理 Git 镜像、Manifest、Blob 缓存；提供 TTL、容量上限、清理与校验命令；支持 `--offline` 只用缓存。

**交付**：`src/cache.emo`、`pokerface cache ls` / `cache rm` / `cache verify`、缓存测试。

**验收**：第二次 pull 在断网时可用；损坏缓存能被识别并淘汰；容量上限生效；`cache rm` 不误删非 pokerface 目录；并发读写安全。

**依赖**：T1.7、T1.14 · **预估**：2-3h

> **备注**（2026-11-18，约 3h）：完成。`src/cache.emo` 统一管理整个缓存：Git 镜像、Manifest envelope、内容寻址 Blob，以及 ref → commit 映射；`src/commands/cache.emo` 实现 `cache ls` / `rm` / `verify`。**安全**：根目录由 `.pokerface-cache` 标记文件标识；`ensure_root` 只接管空目录或仅含已知子目录的目录（T1.14 布局）并写入标记，其他目录一律拒绝，因此 `cache rm` 不会误删无关目录。破坏性操作通过 `<root>/.lock` 目录串行化，删除时按 stat 报告的类型判断、绝不跟随符号链接。**Manifest** 改为单文件 JSON envelope（body + 元数据），用带 pid 的 `.part` 名原子写入，并发写同一个 key 不会出现 body/元数据错配；旧的两文件格式可被接管，遗留文件由 verify 清理。**Refs** 为 `<sha256(git_url\nref)> -> commit`，每次在线解析都会写入（写入前先 ensure_root），`--offline` 读取它，因此分支/标签名无需完整 SHA 也能离线拉取。**容量**：`POKERFACE_CACHE_TTL`（秒或 `<n>s/m/h/d`）与 `POKERFACE_CACHE_MAX_SIZE`（字节或 `<n>K/M/G/T`，1024 进制）在 settings 中解析，每次成功 pull 后尽力执行；先按 TTL 过期，再按最旧优先淘汰到上限内。**命令**：`cache ls`（人类/JSON）、`cache verify [--check]`（默认修复：Blob 哈希、Manifest envelope、ref 映射、Git 镜像 `git fsck`；仍有问题则退出 1）、`cache rm [--all|--git|--manifests|--blobs|--refs]`（清空选中分区，保留根目录和标记，根目录不存在时为空操作）。测试：`test/cache_cmd.emo` 20 个、`test/settings.emo` 3 个容量解析用例、`test/cli.emo` 2 个 cache 路由用例，且 T1.14 的完整命令测试新增同 ref 的离线二次拉取；`emo test` 199/199。**已手工验证**真实缓存（由真实 pull 经 Docker/skopeo 路径填充）：`cache ls` 正确显示 git/manifests/blobs/refs，`verify` 干净；破坏一个 Blob 后 `verify --check` 退出 1、`verify` 将其淘汰；`cache rm --manifests` 与 `cache rm` 只清对应分区且标记保留；外部目录被拒绝且哨兵文件完好；停掉注册表后按分支名离线拉取成功。测试镜像已删除。文档：`docs/spec/cache.md`、`docs/spec/pull.md`、`docs/spec/config.md`、`docs/cli.md`、`docs/notes/git-cache-layout.md`。踩坑：Emo 没有 `else if`（要嵌套 `else`）；`os` 没有 stat，缓存通过 runner 调用 BSD `stat -f "%z %m %HT"` / GNU `stat -c "%s %Y %F"`；`write_atomic` 必须用带 pid 的临时文件名，否则同一 key 的两个写者会共用 `.part`；首次在线 pull 必须先 `ensure_root` 再 `write_ref`，因为 refs 目录尚不存在（手工冒烟时发现）。

#### T1.16 错误模型、退出码与日志

**目标**：定义稳定的错误分类与退出码，给人看的错误带下一步建议，给脚本的结果可用 `--json` 消费。日志默认简洁，`--verbose` 输出请求 / 命令细节但不泄露 token。

**交付**：`docs/spec/errors.md`、`src/errors.emo`、表驱动测试。

**验收**：用法错误、Git 错误、元数据错误、认证错误、网络错误、完整性错误、运行时错误各有固定退出码；错误输出包含可执行的修复建议；`--verbose` 下 token、Authorization header、预签名 URL 查询串被脱敏。

**依赖**：T1.1 · **预估**：2h

> **备注**（2026-11-18，约 2h）：完成。`src/errors.emo` 定义稳定模型：种类 `failure/usage/git/metadata/authentication/network/integrity/runtime`，退出码 1、2、3、4、5、6、7、8（常量在 `src/common.emo`）。命令通过 `errors.report` / `usage_report` / `report_kind` 上报：人类输出一行错误加一行 `hint:` 修复建议；`--json` 时在 **stderr** 输出单个错误对象，stdout 只留给正常结果。分类器先把消息转小写，再按刻意设计的顺序判断：`runtime:` 前缀、用法短语、完整性、网络、认证、锁/配置元数据（先于通用 `git:` 前缀，因此经 Git 读取的锁缺失归为 metadata）、`git:`/`git cache:`、更宽的元数据短语，最后 `failure`。`Logger` 只在 `--verbose` 时通过可注入的 `LogSink`（生产用 `StderrSink`，测试用 `BufferSink`）输出，并脱敏 `Authorization`/`Proxy-Authorization`/`Cookie`/`Set-Cookie` 值、URL userinfo 与查询串（预签名、token 的 `service`/`scope`）、自由文本中的 URL，以及命令参数中的 URL；body 永不记录。接线：pull 记录 settings/步骤细节、通过新 `registry.LoggingTransport` 记录 registry 请求、通过传给 `RegistryBlobTransport` 的 logger 记录 Blob GET、并记录导入 argv；`cache verify` 在仍有问题时以完整性码 7 退出。测试：`test/error_model.emo` 20 个表驱动用例（分类、退出码、hint、JSON 转义/脱敏、sink 捕获、report 返回码），`test/cache_cmd.emo` 1 个完整性退出码用例，以及更新后的 resolve/cache 断言；`emo test` 220/220。手工验证：离线缓存缺失输出 metadata hint 并退出 4；`--json` 在 stderr 输出错误对象；外部目录 `cache rm` 退出 4 且哨兵完好；未知选项退出 2；损坏缓存 `verify --check` 退出 7、修复后退出 0；真实 verbose pull 打印了脱敏后的 manifest/blob 请求与 skopeo 命令，无任何 secret。文档：`docs/spec/errors.md`、`docs/cli.md`、`docs/spec/cache.md`、`docs/spec/pull.md`。踩坑：`case` 模式必须是字面量——`const` 名字是绑定模式，所以退出码/hint 表用字符串字面量；接口方法必须声明返回类型（`def write(text String) Void`）；分类顺序就是契约（runtime 前缀最先，锁/配置先于 Git）；错误 JSON 走 stderr，避免 `--json` 管道把错误当数据；脱敏同时发生在 `report_error`/`error_json` 与 logger，任何输出路径都不会出现未脱敏 URL。

#### T1.17 M1 测试基线、E2E 脚本与规范文档

**目标**：补齐 M1 的测试与文档，让后续改动有回归保护。用本地 fixture Git 仓库 + Emo 写的 mock Registry / CDN 覆盖完整链路。

**交付**：`scripts/e2e-m1.sh`、mock 服务、`docs/spec/` 下的 YAML / lock / config / errors 文档汇总、README 的 M1 使用示例（英文 / 中文同步）。

**验收**：`emo test` 通过；`scripts/e2e-m1.sh` 在干净临时目录可重复运行；不依赖真实 Docker Hub；文档中的命令与实际输出一致。

**依赖**：T1.1-T1.16 · **预估**：2-3h

> **备注**（2026-11-18，约 2h）：完成。`scripts/e2e-m1.sh` 是可重复、完全本地的 M1 端到端脚本：构建 CLI 与 `mock/m1_fixture.emo`，从 `test/fixtures/oci` 组装 OCI Layout，创建本地 Git 仓库并让锁指向 loopback mock registry，然后执行 `resolve`、`pull`（导入检测到的 Docker/Podman/containerd）、停掉 mock 后再 `pull --offline`、`cache ls`、`cache verify`，以及损坏缓存腿（`verify --check` 退出 7，修复后退出 0）。mock 是一个 loopback `httpd` 服务，同时扮演 registry（`/v2/`、按 digest 提供 manifest、blob GET → 307）和 CDN（`/cdn/<hex>`），读取准备好的布局；就绪行用裸 `os.write(1, …)` 输出，脚本轮询不会卡在 stdio 缓冲上。没有 skopeo + 运行时的情况下，脚本仍会跑 resolve/manifest/blob/cache，并确认 pull 以退出码 8 结束。`KEEP_TMP=1` 保留临时目录与日志；默认 trap 会清理临时目录、停止 mock（其 accept loop 子进程用 `pkill -P`）与 CLI 残留的调度器 worker（按本次运行的二进制路径匹配），并删除导入的镜像。`docs/spec/README.md` 汇总所有 M1 规范（YAML、lock、config、errors、registry client、pull、OCI layout、runtime import、cache）与流程；README（英/中）新增与实际输出一致的 M1 示例、更新后的失败回退说明，并勾选路线图条目。`emo test` 220/220；E2E 已用 Docker 29.9.3 + skopeo 1.25.2 完整跑通。踩坑：c target 的调度器在 CLI 主进程退出后仍会留下空闲 worker 进程，它们继承 stdout，所以用 `$(...)`/管道包住 CLI 会挂起——脚本把每次 CLI 调用的输出重定向到文件，并由 trap 按二进制路径清理；`httpd.serve` 的 accept loop 是子进程，停 mock 前要先 `pkill -P` 主进程；小的 gzip fixture 由 `httpd` 完整提供（之前 29MB 失败是大 body 场景，不是 NUL 截断）；fixture 是 linux/amd64 跑在 arm64 主机上，因此 E2E 用 `docker image inspect` 校验导入结果（可运行镜像的 `docker run` 已在 T1.14 手工验证）。M1（T1.1-T1.17）到此完成。

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
| [x] | T2.1 | 服务骨架、配置与健康检查 | T1.2 | 2h |
| [x] | T2.2 | SQLite 数据层与迁移 | T2.1 | 2-3h |
| [x] | T2.3 | OCI Manifest / Index 模型与校验 | T1.5 | 2-3h |
| [x] | T2.4 | BlobStore 接口与本地文件后端 | T2.1 | 2h |
| [x] | T2.5 | AWS SigV4 签名与预签名 URL | T2.1 | 3h |
| [x] | T2.6 | S3 / MinIO BlobStore 适配 | T2.4、T2.5 | 3h |
| [x] | T2.7 | `/v2/` 基础协议与错误格式 | T2.1、T2.2 | 1-2h |
| [x] | T2.8 | Manifest GET / HEAD 与 tag / digest 解析 | T2.2、T2.3、T2.7 | 3h |
| [x] | T2.9 | Blob GET 与 307 预签名重定向 | T2.4、T2.6、T2.8 | 2-3h |
| [x] | T2.10 | Blob 上传：POST / PUT | T2.4、T2.7 | 3h |
| [x] | T2.11 | 分块上传与断点续传：PATCH / GET / DELETE | T2.10 | 3h |
| [x] | T2.12 | Manifest PUT 与 tag 更新 | T2.3、T2.10、T2.11 | 2-3h |
| [x] | T2.13 | 解析 / 元数据 API | T2.8、T2.12 | 2h |
| [x] | T2.14 | 认证与 Token 服务 | T2.7 | 3-4h |
| [x] | T2.15 | 缓存头、ETag 与 CDN 行为 | T2.8、T2.9 | 2h |
| [x] | T2.16 | Tag 列表与分页 | T2.12 | 2h |
| [x] | T2.17 | 部署编排：Registry + MinIO + Caddy | T2.6、T2.14 | 3h |
| [ ] | T2.18 | 可观测性与审计 | T2.1 | 2-3h |
| [x] | T2.19 | 协议冒烟与一致性测试 | T2.1-T2.18 | 3h |

### 5.3 任务详情

#### T2.1 服务骨架、配置与健康检查

**目标**：建立 Registry 服务入口，使用 `httpd` 注册路由，支持 YAML + 环境变量配置、`/healthz`、`/readyz`、优雅停机与请求大小限制。

**交付**：`registry/main.emo`、配置结构体与校验、健康检查、`docs/spec/registry-config.md`。

**验收**：`emo build` 通过；`/healthz` 返回 200；数据库或对象存储不可用时 `/readyz` 返回非 200；收到 SIGTERM 后停止接收新请求并完成在途请求；配置缺失时有明确错误。

**依赖**：T1.2 · **预估**：2h

> **备注**（2026-11-18，约 2h）：完成。`registry/config.emo` 加载必需的 YAML（`--config` > `POKERFACE_REGISTRY_CONFIG` > `./registry.yaml`），逐层拒绝未知字段，支持环境变量覆盖，并产出一个已校验的配置值（listen 127.0.0.1:5000、data_dir、fs/s3 store、body/header/超时限制、shutdown 文件）。`registry/health.emo` 提供 `GET /healthz`（200 ok）、`GET /readyz`（用带 pid 的探针文件检查可写的 `data_dir` 与 fs store root；s3 在 T2.6 前报未就绪；503 body 逐项说明原因）、T2.7 之前的 `/v2/` 200 占位、非 GET 405、其余 404。`registry/main.emo` 用 `httpd.serve_with` 绑定，应用配置的 max body/header 与 read/idle 超时，向 stdout 打印供 supervisor 使用的 `LISTEN=`/`SHUTDOWN_FILE=`，并一直服务到 shutdown 标记出现。**停机**：Emo 没有自定义信号处理器，因此服务忽略 SIGTERM/SIGINT，轮询 `<shutdown_file>`；新增的 `scripts/run-registry.sh` 负责接收信号——收到 TERM/INT 后写入标记并等待，服务的 `stop()` 关闭监听、`wait()` 完成在途请求（空闲 keep-alive 由 `idle_timeout` 兜底）。`registry/registry.example.yaml` 与 `docs/spec/registry-config.md` 记录字段、环境变量、端点、检查项与信号约束。测试：配置 10 个（解析/默认/优先级/环境变量/未知字段/非法值）+ 健康 6 个；`emo test` 236/236。已手工验证：launcher 启动服务，`/healthz`、`/readyz`、`/v2/` 均 200，`POST /healthz` 405；把 `data_dir` 指向普通文件后 `/readyz` 返回 503 并带路径与原因；对 launcher 发 SIGTERM 后日志出现 `shutting down`/`stopped` 且端口关闭；配置缺失时退出 1 并给出路径与两种补救方式。踩坑：`httpd.serve_with` 需要独立的箭头块（`const handler = -> (req httpd.Request) { … }`），附着式 block 只能填最后一个参数；超时选项用 `Int64.to_float64()`；按验收要求配置文件是必需的，相对路径相对进程 cwd；直接对服务二进制发信号会被忽略（设计如此），supervisor 必须走 launcher 或自己 touch 标记。

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

> **备注**（2026-11-18，约 2.5h）：已完成。`registry/db.emo` 封装标准库 `sqlite3` 包（已作为 c-target 依赖加入）：`open`/`connect` 应用 WAL、`synchronous=NORMAL`、`busy_timeout=5000`、`foreign_keys=ON`，随后 `migrate` 在 `BEGIN IMMEDIATE` 中把每个版本写入 `schema_version`，并在事务内复查版本，两个同时启动的服务不会重复应用同一迁移。Schema v1 就是任务建议的五张表及其约束：仓库名唯一、manifests 上 `UNIQUE (repository_id, digest)`、tags 上 `PRIMARY KEY (repository_id, tag)` 加复合外键（tag 必须指向同仓库的 manifest）、`CHECK (size >= 0)`、uploads 的 `CHECK (state IN (...))`；删除仓库会级联删除。CRUD 覆盖五张表，用哨兵值（0、-1、""）代替 `Option`，并提供 `begin`/`commit`/`rollback` 供 T2.8 的多行写入使用。配置新增 `db_path`（默认 `<data_dir>/registry.db`，环境变量 `POKERFACE_REGISTRY_DB_PATH`），`/readyz` 新增 `db` 检查——`registry.db.Health` 每次探测新建短连接（httpd 是一连接一进程，共享句柄会被 fork 进每个请求进程），并先读 16 字节文件头，因此目录或垃圾文件会返回 503 而不是直接断连；已验证该检查在不重启的情况下 200→503→200。**测试拆分**：sqlite3 包仅支持 c target，而 `emo test` 永远走解释器（E3009），所以纯逻辑（迁移顺序、建表/约束文本、pragma、路径处理、`ensure_parent`）放在 `test/registry_db.emo` 由 `emo test` 覆盖，真实数据库由 `registry/db_selftest.emo` + `scripts/check-registry-db.sh` 覆盖——62 项检查，含全部 CRUD、外键级联、`CHECK` 约束、重开后的迁移幂等性、以及写连接/读连接并存。另外用系统 `sqlite3` 命令确认生成的文件 `schema_version` 为 1、`journal_mode=wal`。注意：Emo 的字段在 `init` 之后不可变（用 `Box` 改值）；`PRAGMA journal_mode=WAL` 要求文件所在路径可写，`db_path` 指向目录时启动失败、打印 SQLite 自己的报错并以 1 退出；`emo build` 拒绝 `test/` 下的入口，所以编译版检查器放在代码旁边。

#### T2.3 OCI Manifest / Index 模型与校验

**目标**：实现 OCI Image Manifest、Image Index、Image Config 的解析与编码；校验 descriptor 的 media type、digest、size；支持按平台选择子 Manifest。

**交付**：`registry/oci.emo`、golden fixtures、解析 / 校验测试。

**验收**：真实镜像的 Manifest 可解析；缺字段 / digest 格式错误 / size 不匹配被拒绝；编码后的字节可复现；Index 的平台选择与客户端一致。

**依赖**：T1.5 · **预估**：2-3h

> **备注**（2026-11-18，约 2h）：已完成。`registry/oci.emo` 定义了 `Descriptor`、`Platform`、`IndexEntry`、`ImageManifest`、`ImageIndex`、`ImageConfig` 和一个 `Document` 包装（kind + 两种形态，Emo 没有和类型）。`parse_document` 从 `Content-Type`（去掉参数）或 body 的 `mediaType` 取类型，两者不一致即报错，再分派；`parse_manifest`/`parse_index` 接受调用方给出的类型；`parse_config` 读取 architecture/os/rootfs diff_ids 和 `config.Labels`。校验是全覆盖的，全部返回错误元组：schemaVersion 必须为 2、必需成员与 JSON 类型检查、digest 必须是 `sha256:` + 64 个小写十六进制、media type 必须是 `type/subtype` 且不含空白、size 必须是非负整数、annotation 必须是字符串。`verify_body` 对 body 计算哈希和字节数并与 descriptor 比对，不一致时同时报出两侧。编码用 `json.object` 固定字段顺序、紧凑分隔符，测试与新增的 golden fixture 逐字节比对，并验证 encode→parse→encode 稳定。`select_platform` 返回第一个 os+arch 完全匹配的条目（忽略 variant），与 `src/registry.emo` 一致，miss 时的 "available:" 信息也一样。Fixture：在现有 skopeo 可读镜像之上的多架构 `index.json`、`manifest.docker.json`，以及 `manifest.canonical.json`/`index.canonical.json`。`test/registry_oci.emo` 17 个测试；`emo test` 264/264。注意：反向守卫（`if !value.is(...) { return ... }` 之后再调用具体类方法）不会收窄类型，数组/对象解析都要写成正向分支；body 自身没有 `mediaType` 时 `parse_manifest(body, "")` 会报错，所以构造最小 body 的测试显式传入类型。编码是规范化而非无损——未知成员会被丢弃，registry 仍存储并返回客户端原始字节。

#### T2.4 BlobStore 接口与本地文件后端

**目标**：定义 Blob 存储抽象：`put`、`get`、`head`、`delete`、`presign_get`。本地文件后端用于开发和测试，路径以 digest 内容寻址。

**交付**：`registry/blobstore.emo`、本地后端、接口测试。

**验收**：写入采用临时文件 + 原子 rename；读取支持 Range；路径不穿越出根目录；重启后数据仍在；`presign_get` 在不支持预签名的后端返回空值，由上层回退到直接流式返回。

**依赖**：T2.1 · **预估**：2h

> **备注**（2026-11-18，约 2h）：已完成。`registry/blobstore.emo` 定义 `BlobStore`（`put`、`put_file`、`get`、`read_range`、`head`、`delete`、`presign_get`）和 `LocalStore`，布局为 `<root>/sha256/<hex>` 加一个很小的 `<hex>.size` 记录。需要该记录是因为 Emo 的 `os` 没有 `stat`、`file` 只能整文件读取——否则 HEAD/Content-Length 就要把整个 layer 读一遍。写入时流式拷贝到 `.tmp-<pid>-<hex>` 并边写边算哈希和字节数，digest 不符则删除临时文件且什么都不留下；随后用同样的临时文件+rename 写 size 记录，最后把 blob rename 到位——rename 就是提交点，读方永远看不到半个 blob；两次 rename 之间崩溃只会留下无害的孤儿记录,下次 put 会修复。重复 put 同一 digest 是空操作（只存一份）。`read_range` 校验非负 offset/length，越界报错，EOF 处截断；`head` 对缺失返回 exists=false，对“文件在但记录缺失”返回 size=-1；`delete` 同时删两者并返回 blob 是否存在；`presign_get` 返回 "" 由上层回退流式。缺失内容统一为 `blobstore: not found: <digest>`，配 `is_not_found()` 判定。digest 校验抽到新的 `registry/digest.emo`（`registry/oci.emo` 共用），路径只由校验过的 hex 拼出——`..`、`/`、其它算法、大写十六进制都在任何文件操作之前被拒绝。`registry/main.emo` 启动时打开 fs store（创建 `<root>/sha256`），根目录是文件时以 1 退出并打印路径与原因，已手工验证 `/readyz` 200 与生成的目录结构。测试：`test/registry_blobstore.emo` 14 个（往返+重启、去重、不符残留、跨 64 KiB 的流式 put_file、未找到、Range 截断、路径穿越、delete 幂等、空 blob、记录缺失修复、接口一致性、根目录被文件占用）；`emo test` 278/278。踩坑：Emo 没有带类型的 `const`，接口一致性通过把 `LocalStore` 传给 `BlobStore` 类型的辅助函数来验证；`os.open_read` 是唯一廉价的存在性检查（没有 stat），所以存在性与大小分两个文件。

#### T2.5 AWS SigV4 签名与预签名 URL

**目标**：用 `crypto` 的 HMAC-SHA256 实现 AWS Signature V4 的请求签名与查询串预签名，兼容 MinIO 的 path-style 访问。

**交付**：`registry/sigv4.emo`、官方测试向量、固定时间源的单元测试。

**验收**：签名结果与 AWS 测试向量一致；预签名 URL 在有效期内可访问、过期后拒绝；URI 编码符合 SigV4 要求；密钥与签名不出现在日志中。

**依赖**：T2.1 · **预估**：3h

> **备注**（2026-11-18，约 2h）：已完成。`registry/sigv4.emo` 把整个算法写成注入 `time.Time` 的纯函数：规范化请求（编码后的 URI、规范化查询串、规范化请求头、签名头名、payload 哈希）、待签字符串、HMAC 密钥链、签名。两个入口：`sign_request` 自动加 `x-amz-date`（覆盖调用方给的值）、会话 token，并把 `authorization` 放到最后；`presign` 生成查询串形式（`UNSIGNED-PAYLOAD`、只签 `host`、`X-Amz-Signature` 追加在最后），返回 `PresignedUrl`，其 `valid_at(now)` 正好覆盖 `[signed_at, signed_at + expires_in)`。编码完全遵循 SigV4（空格 `%20`、按 UTF-8 字节大写十六进制、URI 里保留 `/` 而查询值里 `%2F`、参数先按编码后的名再按值排序；头名小写、去首尾空白、内部空白折叠、排序、重名逗号合并）。**官方向量一次通过**：aws-sig-v4-test-suite 的 `get-vanilla`（`5fa00fa3…`）、`get-vanilla-query-order-key`（`eedbc4e2…`），以及 S3 预签名示例（`aeeed9bb…`），共同覆盖了规范化请求、编码、日期 scope 与 HMAC 链。`test/registry_sigv4.emo` 12 个测试：向量、编码、查询/头规范化、两种模式的会话 token、调用方日期/authorization 覆盖、时钟与密钥敏感性、有效期边界秒、UTF-8 路径；`emo test` 290/290。模块不写任何日志，secret 只作为 HMAC key 使用；测试还断言预签名 URL 中不会出现 secret。踩坑：没有 `else if`；`Bytes.get` 直接返回 Int64（没有 `to_int64`）；数组没有排序，规范化排序是对编码后的键值对做插入排序（参数数量很小，足够）。后续：重试与日志在 T2.6，必须对 Authorization 与预签名 URL 脱敏。

#### T2.6 S3 / MinIO BlobStore 适配

**目标**：基于 SigV4 实现 S3 兼容存储后端，支持 PUT / GET / HEAD / DELETE 与 GET 预签名；配置 endpoint、bucket、region、access key、secret key、TLS、path-style。

**交付**：`registry/s3_blobstore.emo`、MinIO 集成测试、配置示例。

**验收**：对 MinIO 完成上传 / 下载 / 预签名访问；bucket 不存在时启动失败并提示；TLS 与自签 CA 可配置；网络错误有重试与清晰错误；不在日志中输出密钥。

**依赖**：T2.4、T2.5 · **预估**：3h

> **备注**（2026-11-18，约 3h）：已完成，但有一个环境限制（见下）。`registry/s3_blobstore.emo` 用签名 HTTP 实现 BlobStore：path-style 与 virtual-host 两种寻址、键为 `[prefix/]sha256/<hex>`、可注入 transport（真实实现根据 `ca_file`/`verify_tls` 构造 TLS 选项），启动时对 bucket 发签名 HEAD——404 报出 bucket 名与 endpoint，403 点出两个凭据配置项但不打印值。`store.s3.*` 接入配置，含严格未知字段检查、环境变量覆盖与校验（endpoint scheme/路径、bucket、region、凭据、presign ttl 1–604800）；summary 只打印 `access_key=<set>`，从不输出密钥。请求签名包含 `host`（默认端口被去掉，保证与线上 Host 一致）、`x-amz-content-sha256` 以及额外头（`content-type`、`range`、会话 token）；签名用的 Host 条目在发送前移除，因为 stdlib 客户端自己写 Host。传输错误与 5xx 重试 3 次并退避，4xx 不重试；错误文本带方法/URL/状态和 S3 的 `<Code>`，绝不带 body 或密钥。**实测发现的坑**：`head` 不能用 HEAD——stdlib http 客户端在 HEAD 响应里也会读 `Content-Length` 个字节，而 S3 的 HEAD 只报大小没有 body（连接在读取中途断开）。现改为 ranged GET（`bytes=0-0`），从 `Content-Range` 取总大小；空对象由 416 回退到普通 GET，忽略 Range 的服务端由 200 计数兜底。健康检查改为向 backend 询问 `BlobHealth.probe()`，两种存储的 /readyz 都成立（LocalStore 探测 digest 目录，S3Store HEAD bucket）。测试：`test/registry_s3.emo` 20 个——注入 transport 的协议覆盖，加上 `POKERFACE_TEST_S3_*` 设置时的真实往返（put/get/head/range/预签名下载/过期 403/delete）；mock `mock/s3_fixture.emo` 会验签与校验预签名有效期并把对象落盘，由 `scripts/e2e-s3.sh` 启动；`emo test` 314/314。已手工验证服务跑 s3 后端：启动 bucket 检查、`/readyz` 200、summary 脱敏、bucket 不存在时退出 1 并给出清晰信息。**限制**：本机无法访问 Docker Hub（`docker pull minio/minio` 超时），所以没能运行 MinIO 本体；真实往返是对本地会验签的 fixture 跑的。把 `POKERFACE_TEST_S3_*` 指向 MinIO 即可运行同一测试。

#### T2.7 `/v2/` 基础协议与错误格式

**目标**：实现 `GET /v2/`，返回 `Docker-Distribution-API-Version: registry/2.0`；统一 OCI 错误 JSON：`{"errors":[{"code","message","detail"}]}`；补全 401 / 404 / 405 的响应。

**交付**：路由与中间件、错误响应辅助函数、协议测试。

**验收**：无认证模式 `GET /v2/` 返回 200；开启认证后由 T2.14 覆盖 401 挑战；未知路由返回 404；方法不匹配返回 405 并带 `Allow`；所有错误响应符合 OCI 错误格式；响应带 request id。

**依赖**：T2.1、T2.2 · **预估**：1-2h

> **备注**（2026-11-18，约 1.5h）：已完成。`registry/api.emo` 负责 distribution API 的外层：`GET /v2/`（以及 `/v2`）返回 200 `{}` 与 `Docker-Distribution-API-Version: registry/2.0`；所有响应（成功与错误）都带 `X-Request-Id`；所有错误都走 OCI 信封（`error_body`/`error_response`/`not_found`/`bad_request`/`method_not_allowed`/`unauthorized`，并导出完整错误码常量 BLOB_UNKNOWN … TOOMANYREQUESTS）。未知路由返回 404 `NAME_UNKNOWN`，`detail` 为 `"<METHOD> <path>"`；`/v2/` 方法不匹配返回 405 带 `Allow: GET` 与 `UNSUPPORTED`；401 助手（挑战头 + UNAUTHORIZED 码）留给 T2.14 使用。请求 id 仅在客户端 `X-Request-Id` 为 1–64 个 `[A-Za-z0-9._-]` 时回显（CR/LF 无法通过回显注入），否则生成 `pf-<pid>-<monotonic ns>`，在每连接一进程的模型下无需共享状态即可唯一。健康检查路由移到 `handle_health`，由路由器在兜底之前分派，`/healthz`、`/readyz` 仍返回纯文本。测试：`test/registry_api.emo` 12 个（探测与响应头、405/404 信封与 detail、健康分派、id 回显与净化、生成的 id 唯一、带/不带 detail 的信封形状、400 助手、401 挑战、公共头不重复）；`emo test` 326/326。已通过真实 HTTP 验证：`/v2/` 带版本头与 request id，`POST /v2/` 返回 UNSUPPORTED JSON 与 Allow，`/nope` 返回 NAME_UNKNOWN，客户端 `X-Request-Id` 被回显。踩坑：Emo 没有字符串比较运算符（id 字符集用 `index_of` 判断）；测试里用命名参数构造 `httpd.Request` 代替不存在的工厂函数。

#### T2.8 Manifest GET / HEAD 与 tag / digest 解析

**目标**：实现 `/v2/<name>/manifests/<reference>`，其中 `<name>` 可含 `/`；reference 支持 tag 与 digest；处理 `Accept`，返回原始 Manifest 字节与 `Docker-Content-Digest`、`Content-Type`、`Content-Length`。

**交付**：路由、查询逻辑、HEAD 支持、测试。

**验收**：按 tag 与 digest 均可取；不存在返回 404 `MANIFEST_UNKNOWN`；HEAD 不返回 body；digest 不匹配时拒绝；多架构 Index 可正常返回。

**依赖**：T2.2、T2.3、T2.7 · **预估**：3h

> **备注**（2026-11-18，约 2.5h）：已完成。`registry/manifests.emo` 提供 `GET|HEAD /v2/<name>/manifests/<reference>`：路径按 `/manifests/` 切分，所以仓库名可以带斜杠；digest 形式的 reference 直接使用，tag 经 tags 表解析，找不到返回 404 `MANIFEST_UNKNOWN`，detail 为 `<repo>:<reference>`。`sha256:` 开头但不是合法 digest 的 reference 返回 400 `DIGEST_INVALID`。每次读取都会重新计算存储字节的哈希，与行内 digest 不符时返回 500 `UNKNOWN`（两侧 digest 都写进 detail）——registry 绝不返回与名字矛盾的字节。`Accept` 会解析（逗号分隔、去掉参数、大小写不敏感、`*/*`），不匹配时返回 404 而不是返回客户端无法使用的类型。响应带 `Content-Type`、`Docker-Content-Digest` 和显式 `Content-Length`；HEAD 只有头没有 body（httpd 会去掉 body）。存储访问是 `ManifestStore` 接口：handler 测试用 fake，`DbManifests` 是 SQLite 实现，每次请求开一个短连接（一连接一进程，不能共享句柄）。路由器从 `api.emo` 移到 `registry/router.emo`，用 `Service` 携带 config/db/blob/manifests——`api.emo` 只保留信封、id 和装饰，避免 api↔manifests 模块环。测试：`test/registry_manifests.emo` 13 个 handler 测试（tag/digest 读取、HEAD、404、500、digest 不符、Accept 各种形态、index 原样返回、400、405、路径形状、路由器装饰），加上编译版 `db_selftest` 中 5 项 `DbManifests` 检查；`emo test` 338/338，db selftest 70/70。已通过真实 HTTP 对预置 SQLite 数据验证：tag/digest GET 返回精确字节与 digest 头，HEAD 无 body 且长度正确，缺失 tag 是 OCI 404，Accept 不匹配的 404 detail 带存储类型，POST 是 405 且 `Allow: GET, HEAD`。踩坑：没有 `String.upper`（Accept 大小写测试用混合大小写字面量）；manifest 路由必须排在裸 `/v2/` 探测与兜底之前。

#### T2.9 Blob GET 与 307 预签名重定向

**目标**：实现 `/v2/<name>/blobs/<digest>`。使用 S3 时返回 307 + `Location` 预签名 URL；使用本地文件后端时直接流式返回 200。HEAD 返回元数据，不重定向。

**交付**：Blob GET / HEAD、预签名 TTL 配置、测试。

**验收**：307 的 Location 可直接下载且过期失效；本地后端返回正确 `Content-Length` 与 `Docker-Content-Digest`；不存在返回 404 `BLOB_UNKNOWN`；客户端可通过两种模式完成下载。

**依赖**：T2.4、T2.6、T2.8 · **预估**：2-3h

> **备注**（2026-11-18，约 2h）：已完成。`registry/blobs.emo` 提供 `GET|HEAD /v2/<name>/blobs/<digest>`：路径按 `/blobs/` 切分（仓库名可含斜杠），先校验 digest（非法 → 400 `DIGEST_INVALID`），再要求 `blobs` 表把 digest 关联到该仓库、且后端对象存在——任一缺失都是 404 `BLOB_UNKNOWN`，detail 为 `<repo>@<digest>`。S3 模式下 GET 返回 307 + 预签名 Location（不经 registry 代理字节）；文件系统模式下 `presign_get` 返回 ""，路由回退到本地字节，带 `Content-Type`、`Docker-Content-Digest`、`Content-Length`。HEAD 从不重定向，直接返回元数据，优先用存储的大小记录，缺失时回退到数据库记录的大小。两种方法都先查 store 的 head，这样“数据库有记录但对象缺失”在本服务返回 404 而不是把 404 推给 CDN。链接查询是 `BlobLinks` 接口（`DbBlobLinks` 每请求短连接）；Service 现在分别携带 blob 健康探针与完整 BlobStore，`serve` 因此把具体 store 传两次——具体类型→接口是结构化兼容，health 仍只需要 `BlobHealth`。测试：`test/registry_blobs.emo` 14 个路由测试，编译版 `db_selftest` 新增 4 项 `DbBlobLinks` 检查；`emo test` 351/351，db selftest 75/75。已通过真实 HTTP 验证两种模式：fs GET/HEAD 返回精确字节/长度与 digest 头，缺失与非法 digest 是 OCI 404/400，POST 是 405 带 `Allow`；配合 S3 fixture，GET 返回 307，跟随 Location（fixture 会验签）成功下载对象，HEAD 是不带 Location 的直接 200。踩坑：本地路径同样会调用 `presign_get` 再回退（T2.4 的契约），测试要预期这次调用；httpd 对 307 打印的 reason phrase 是 "Unknown"（HTTP 上合法，包内没有该短语）。

#### T2.10 Blob 上传：POST / PUT

**目标**：实现最小 OCI 上传流程：`POST /v2/<name>/blobs/uploads/` 创建会话，`PUT ...?digest=sha256:...` 上传完整 Blob；校验 digest 与 size，去重，清理过期会话。

**交付**：上传路由、会话表、单块上传测试、`curl` 示例。

**验收**：上传成功后 `HEAD` 可见；digest 不匹配返回 400 且不落盘；重复 Blob 不重复存储；过期会话可清理；上传大小限制生效。

**依赖**：T2.4、T2.7 · **预估**：3h

> **备注**（2026-11-18，约 2.5h）：已完成。`registry/uploads.emo` 实现最小 OCI 流程：`POST /v2/<name>/blobs/uploads/` 开会话（202，相对 `Location` + `Docker-Upload-UUID`；不带尾斜杠的集合路径同样接受），`PUT .../uploads/<id>?digest=…` **先对请求体哈希、再落任何盘**——不匹配返回 400 `DIGEST_INVALID`，存储和会话都不动——然后写入字节、关联 blob（`INSERT OR IGNORE`，重复上传只存一份），并在同一事务里以 `state = 'pending'` 守卫完成会话（并发竞争者输掉转移 → 404）。带 `?digest=` 的 POST 是规范的单请求整块上传，复用同一完成路径。会话是 `UploadSessions` 接口 + `DbUploadSessions`（每请求短连接）；每次 `start` 先清扫过期 `pending` 行（走索引），TTL 暂为模块常量（24h），可配置化留作后续。POST 会创建仓库行，因此按 OCI 语法校验仓库名（每段 `[a-z0-9]+`，分隔符 `.`/`_`/`__`/`-+`，≤255）→ 400 `NAME_INVALID`。大小限制由 httpd 分帧层强制（超过 `limits.max_body_bytes` 直接 413，两种分帧都覆盖）。路由器**先**检查上传路由再看 blob GET 路由（两者都匹配 `/blobs/`）。db.emo 新增 `upload_info`（join 出状态 + 仓库名）与 `complete_pending_upload`（CAS）。测试：`test/registry_uploads.emo` 27 个（两种路径形态、整块 POST、PUT 完成、缺失/非法 digest、不匹配不落盘、未知/已完成/异库会话、store/lookup/complete 失败、假 store 与真实 LocalStore 的去重（含空 blob）、名称表、方法、路径形态、路由分发）+ 编译版 db_selftest 新增 14 项 `DbUploadSessions` 检查；`emo test` 378/378，db selftest 89/89。已用 curl 实测：POST → 202 带 Location/UUID，PUT 带正确 digest → 201 带 `Docker-Content-Digest`，随后 `HEAD /v2/<name>/blobs/<digest>` 能找到该 blob，错误 digest 是 OCI 400 且不落盘，`?digest=` 的 PUT 返回 400。踩坑：`Map.get` 对缺失 key 直接 raise（先 `has`）；`expire_uploads`/`put_blob` 返回标量不是元组；名称校验器起初接受分隔符开头的组件（`-a`）——语法要求段首必须是 `[a-z0-9]`，已显式强制。后续：T2.11（PATCH/GET/DELETE + 并发写拒绝）、可配置 TTL、POST 不匹配时会话将保留 pending 至过期（已写入文档）。

#### T2.11 分块上传与断点续传：PATCH / GET / DELETE

**目标**：补齐 OCI 分块上传：`PATCH` 追加数据、`GET` 查询偏移、`DELETE` 取消会话；支持客户端断点续传。

**交付**：分块上传实现、状态机测试、与 `oras` / `skopeo` 的兼容测试。

**验收**：多段 PATCH 后 PUT 成功；中途 GET 返回正确 `Range`；DELETE 后会话不可用；并发写同一会话被拒绝；异常中断的会话可过期清理。

**依赖**：T2.10 · **预估**：3h

> **备注**（2026-11-19，约 4h，含下述编译器排查）：已完成。`registry/uploads.emo` 补齐 OCI 分块协议：`PATCH` 追加分块，`Content-Range` 的 start 必须等于会话记录的偏移——乱序返回 416 `BLOB_UPLOAD_INVALID`，end 与请求体长度不符或格式非法（拒绝 `bytes=…` 前缀，规范钉死 `^[0-9]+-[0-9]+$`）返回 400；不带 Content-Range 的 PATCH 按流式盲追加（skopeo 的形态）；`GET` 返回 204 带 `Location` + `Range: 0-<最后字节>`（零字节时省略，`0-0` 会被解读为已收 1 字节）；`DELETE` 返回 204，此后对该会话的一切操作都是 404；收尾的 `PUT` 可按同样的偏移规则携带最后一块。分块数据落在 `<data_dir>/uploads/<id>.part`（`os.open_append`），migration 2 新增 `uploads.offset_bytes` 作为权威 CAS 参照；每次追加都在 `BEGIN IMMEDIATE` 内，并发写同一偏移的败者拿 416（PUT 收尾——`store.put_file`、blob 关联、会话完成——占用同一窗口：v0.1 有意让写锁全局化）。PUT 时 digest 不匹配会话与数据原样保留；每次 `start` 内的过期清扫现在也删掉被清扫会话的 part 文件。接口扩展（`append`/`cancel`/`part_path`，`UploadSession` 增加 `offset`），T2.10 的三个 fake 与 Service 构造同步更新。**最重要的发现：c target 拒绝裸方法调用。** 类体内的 `case write_part(id, body)`——不带 `self.` 前缀——能过检查器和解释器，但 IR 会降级成 `Type_ref`，c 代码生成器以 `the c target does not support this expression form (Type_ref)` 拒绝，并拖垮整个包的构建。定位方式是把 registry 树复制到干净目录做二分（一个包被污染后所有入口都失败，单文件探针必须在纯净树上做）；修法是机械的——类方法一律经 `self.` 调用——记录在此，因为检查器应当在读取处拒绝（E5016 式）而不是让代码生成崩掉。测试：`test/registry_uploads.emo` 新增 27 例（流式/带范围 PATCH、416、400、GET/DELETE 状态机、store/lookup/cancel 失败、真实 LocalStore 的 PATCH+PATCH+PUT、PUT 携带末块、skopeo 形态、digest 不匹配保留会话、空 blob、Content-Range 解析）+ db_selftest 新增 14 项（偏移推进与回读、part 文件按序持有分块、取消、带文件清理的过期清扫）；`emo test` 403/403，db selftest 103/103。已用 curl 实测（Content-Range 分块、GET 续传、DELETE、416、单请求 POST），并用真实 `skopeo copy oci:… docker://127.0.0.1:…` 推送（流式 PATCH 形态）。后续：PUT 期间的会话级互斥替代全局写锁、可配置 TTL、硬崩溃留下的孤儿 part 文件。

#### T2.12 Manifest PUT 与 tag 更新

**目标**：实现 `PUT /v2/<name>/manifests/<tag|digest>`，校验 Manifest 中引用的 config / layers 均已存在，写入 Manifest 并原子更新 tag。

**交付**：Manifest 写入、tag 更新、事务测试。

**验收**：`oras push` / `skopeo copy` 可推送成功；引用缺失返回 `MANIFEST_BLOB_UNKNOWN`；tag 更新是原子的；返回 `Docker-Content-Digest`；失败时旧 tag 不被覆盖。

**依赖**：T2.3、T2.10、T2.11 · **预估**：2-3h

> **备注**（2026-11-19，约 2.5h）：已完成。`registry/manifests.emo` 增加写半边：`PUT /v2/<name>/manifests/<tag|digest>` 把请求体**原样**存储在其摘要之下（`ManifestWriter` 接口；`DbManifests.put` 哈希后 `INSERT OR IGNORE`——重复推送保持单行），tag 引用则用单条 `INSERT OR REPLACE` 指向（原子；失败从不扰动旧 tag）。所有校验先于任何写入：经 T2.3 的 `parse_document` 解析（Content-Type 与 body 的 `mediaType` 必须一致，二者可互相补位 → 400 `MANIFEST_INVALID`）、digest 引用必须等于请求体的哈希（400 `DIGEST_INVALID` 带两侧摘要）、tag 必须满足 OCI 语法 `[a-zA-Z0-9_][a-zA-Z0-9._-]{0,127}`（400 `TAG_INVALID`）、仓库名因 PUT 会建行而校验（400 `NAME_INVALID`）。文档引用的一切内容必须已存在：manifest 的 config + layers 对仓库的 blob 关联校验，index 的子项对已存 manifest 校验——首个缺失即 `404 MANIFEST_BLOB_UNKNOWN` 带摘要且什么都没写；校验内部的查询失败单独返回 500，与缺失区分。`subject` 描述符有意不校验（规范要求接受 subject 缺席的 manifest；T2.3 解析器直接丢弃）。成功：`201` + `Location` + `Docker-Content-Digest`。Service 增加 `manifest_writer`（同一个 `DbManifests` 实例兼作两接口），三个 T2.x 测试文件的构造与 GET 测试的 `handle` 调用同步加参。测试：`test/registry_manifest_put.emo` 22 例（tag/digest 推送、不匹配、解析/类型/不一致 400、tag 语法、名称语法、缺 config/layer/子项 → 404 带摘要、空 layers、subject 接受、tag 移动序列、store/tag/link 失败 500、405 与 `Allow: GET, HEAD, PUT`、路由分发）+ db_selftest 10 项（原样回读、摘要应答、重推无操作、tag 指向/更新、未知仓库 tag 拒绝）；`emo test` 425/425，db selftest 114/114。**实测：`skopeo copy oci:… docker://127.0.0.1:…` 推送现在全流程成功**（blob 上传是 T2.11；此前失败的 manifest 步骤落在本次），按 tag 的 GET/HEAD 返回原样字节与 `Docker-Content-Digest`，curl PUT 空 layers manifest 移动了 tag（201，服务新摘要）。踩坑：引用检查辅助函数需要三态应答（存在/缺失/失败）——二元组把 link 存储失败与缺失 blob 混为一谈，本该 500 的答成 404；测试抓到。

#### T2.13 解析 / 元数据 API

**目标**：提供便于 CLI 和运维排查的只读接口：`GET /api/v1/resolve?repository=<name>&tag=<tag>`，返回 digest、media type、平台与可选的 commit 注解（来自 `org.opencontainers.image.revision`）。

**交付**：接口、JSON 响应、认证与测试。

**验收**：tag 存在时返回完整信息；不存在返回 404；无权限返回 401/403；不泄露存储凭据；`pokerface` 可用它作为 Git 元数据缺失时的只读兜底。

**依赖**：T2.8、T2.12 · **预估**：2h

> **备注**（2026-11-19，约 2h）：已完成。`registry/resolve.emo` 提供 `GET /api/v1/resolve?repository=<name>&tag=<tag>`：参数缺失/为空返回 400，名称不合 OCI 语法返回 400 `NAME_INVALID`，未知 tag 返回 404 `MANIFEST_UNKNOWN`（detail 为 `<repo>:<tag>`）；成功返回一份 JSON 文档——repository、tag、digest、media type、`platforms`（index 取自带条目，image manifest 读其 **config blob** 经 blob store；有 variant 则带上）、以及文档 `org.opencontainers.image.revision` 注解中的 `revision`（缺失时省略）。响应从不出现任何凭据或存储配置。认证走路由器：开启认证时该端点需要针对所查名称的 `repository:<name>:pull`（scope 由查询参数计算，401 挑战与 /v2/ 一致）——匿名、跨库、无 pull 的 token 都会失败；未开启认证时公开。响应统一带 API 版本与请求 id。测试：`test/registry_resolve.emo` 14 例（完整文档、缺 revision、index 平台含 variant、400/404/500、仅 GET、无认证路由分发、开启认证的挑战/通过分支）；`emo test` 460/460。实测：skopeo 推送的 tag 解析出 amd64/linux 平台，缺失 tag 404，缺参 400。踩坑：索引元素收窄（`items[0].is(...)` 后 `items[0].entries()`）不通过类型检查——先把元素绑定到局部变量；持有收窄后 `JsonArray` 的 `var` 变量仍是 `Json` 类型，读侧需要再次收窄。

#### T2.14 认证与 Token 服务

**目标**：实现 Bearer Token 流程：`GET /v2/` 返回 401 与 `WWW-Authenticate`；`/token` 支持 Basic 认证换取带 scope 的短时 Token；中间件校验 `repository:<name>:pull|push`。

**交付**：Token 签发 / 校验、scope 中间件、配置示例、负向测试。

**验收**：匿名 pull 被拒绝（若开启认证）；只有 pull scope 不能 push；token 过期后 401；跨仓库访问被拒绝；密码与签名密钥不出现在日志；v0.1 配置文件方式可用。

**依赖**：T2.7 · **预估**：3-4h

> **备注**（2026-11-19，约 3.5h）：已完成。`registry/auth.emo` 实现 Docker 的 Bearer 流程（HS256 JWT）：`GET /v2/` 与所有受保护路由返回 401 + `WWW-Authenticate: Bearer realm="…",service="…",scope="…"[,error="…"]`（realm 默认 `http://<listen>/token`）；`/token` 用 Basic 换取 `{"token","expires_in","issued_at"}`；token 携带 Docker 形态的 `access` 声明（`repository:<name>:pull,push`），路由器里的无状态 gate 校验签名（常数时间）、时间窗（`expired_token`）、签发者与 scope。与 Docker 对齐：认证失败一律 401 带挑战（invalid_token / expired_token / insufficient_scope），客户端可补申请 scope 重试；未知账号与错误密码返回完全相同的 401，比较用常数时间。scope 按空白分隔、逗号连接动作；畸形 scope（坏仓库名、未知动作）返回 400 且不授予任何东西——pull-only token 无法推送（401 insufficient_scope），跨库 token 同样被拒。配置：`auth:` 段（enabled、realm、service、issuer、token_ttl ≥ 60、users、signing_key 或 signing_key_file），严格未知字段检查，`POKERFACE_REGISTRY_AUTH_SIGNING_KEY` / `_AUTH_ENABLED` 环境变量覆盖，密钥文件在加载时读取一次（去尾部换行，内联与文件同设报错），enabled 而缺 key 或 users 是启动错误，摘要打印 `auth=enabled users=<n> signing_key=<set>`——密钥与密码从不进日志（有测试钉死 + 实机 grep）。base64url 用新加的 `base64` 依赖。测试：`test/registry_auth.emo` 新增 25 例（编解码、mint/verify 矩阵、scope 匹配、挑战形态、端点 200/401/400/405、gate 决策含跨库与 pull-only-push、开启认证后的路由挑战、配置段/默认值/env/脱敏）；`emo test` 450/450。**实测：skopeo 全流程可用**——`skopeo login --username alice …` 后 `skopeo copy` 走完挑战/token/推送整个周期；匿名 manifest GET 是 401；签名密钥不出现在服务日志。踩坑：`(R.error, …)` 元组的错误槽静态为 String——gate 不能经错误槽传 Response，因此 `check_token` 返回原因字符串、401 由路由器构建（原因到错误词的映射在 `error_class`）；逗号是单个 scope 内的动作分隔符而非 scope 分隔符（skopeo 实测抓到）；负向 `is()` 守卫不收窄——yaml/json 解析辅助函数经正分支包装接收收窄后的类型。

#### T2.15 缓存头、ETag 与 CDN 行为

**目标**：为不可变 Blob 与可变 Manifest 设置不同的缓存策略；支持 `ETag` / `If-None-Match`；保证 CDN 可缓存 Blob，而 tag 更新能及时生效。

**交付**：响应头中间件、CDN 配置说明、测试。

**验收**：Blob 返回长缓存 + `immutable`；Manifest 返回短缓存或 `no-cache`；`If-None-Match` 命中返回 304；tag 更新后新请求能看到新 digest；不因 CDN 缓存导致旧 Manifest 长期不更新。

**依赖**：T2.8、T2.9 · **预估**：2h

> **备注**（2026-11-19，约 1.5h）：已完成。新增 `registry/cache.emo` 承载策略与验证器：blob 在 GET **与** HEAD 上回答 `ETag: "sha256:…"`（摘要即验证器）与 `Cache-Control: public, max-age=31536000, immutable`；manifest 按 **digest** 拉取时同样不可变，按 **tag** 拉取时为 `public, max-age=60, must-revalidate`——tag 更新在任何遵守规范的 CDN 上最多一分钟生效，旧 manifest 绝不被钉住更久；预签名 307 为 `no-cache`（缓存的重定向可能发放过期签名；MinIO 侧对象字节自带响应头，已写进 CDN/运维文档）。`If-None-Match` 遵循 RFC 7232：`*`、弱 `W/`、逗号列表、可选引号都匹配——命中在进入任何取体工作之前返回 304（同样的验证器、无 body），不匹配返回全新 200；tag 更新后旧 ETag 立即失效（实测：向同一 tag PUT 新 manifest，下一次 GET 立即返回新 digest）。测试：`test/registry_cache.emo` 11 例（匹配器表、blob/manifest GET/HEAD 头、304 形态、307 no-cache、tag 与 digest 两种策略）；`emo test` 470/470。已用 curl 在实机验证（响应头、blob 与 manifest 的 304、tag 更新后的新鲜度）。踩坑：数组没有 `+` 拼接——用 `with_cache` 助手追加策略头；传给 manifests 处理器的 tag/digest 标志起初写反（digest-valid ≠ by-tag），测试抓到。

#### T2.16 Tag 列表与分页

**目标**：实现 `GET /v2/<name>/tags/list`，按字典序返回 tag，支持 `n` 与 `last` 分页，并在有下一页时返回 `Link` 头。

**交付**：路由、分页逻辑、测试。

**验收**：空仓库返回空列表；分页边界正确；`last` 不存在时从合理位置开始；需要 pull 权限；响应符合 OCI 规范。

**依赖**：T2.12 · **预估**：2h

> **备注**（2026-11-19，约 1.5h）：已完成。新增 `registry/tags.emo` 提供 `GET /v2/<name>/tags/list`：tag 按字典序（新的 `db.list_tags_page` 用 `ORDER BY tag`，多取一行以回答 more 标志，无需二次查询），返回 `{"name","tags"}` JSON，`n` / `last` 分页中 `last` 是页起点之后**排他**的 tag **值**，满页且还有更多时带 `Link: </v2/<name>/tags/list?n=<n>&last=<last>; rel="next"`（相对 URI 引用；末页与不带 `n` 的全量列表无 Link）。`n=0` 返回空列表且无 Link；非数字/负数 `n` 是 400 `TAG_INVALID`；仓库不存在是 404 `NAME_UNKNOWN`；存在但无 tag 返回空列表；其他方法 405。查询读实时表，tag 更新天然在下一次分页可见。认证走 gate：列表需要 `repository:<name>:pull`（已加入 `required_access`）。Service 增加 `tags TagList`（接口 + `DbTagList`），七个路由测试文件同步加了 tags fake。测试：`test/registry_tags.emo` 16 例（路由形态、全量列表、空/缺失仓库、页边界与 Link 格式、末页、`n=0`、非法 `n`、方法、认证 401/通过分支）+ db_selftest 8 项钉死 SQL 语义（字典序、排他 `last`、more 标志、越过末尾的空页）；`emo test` 481/481，db selftest 122/122。实测：五个 tag 字典序列出，`?n=2` 带精确 Link，`?n=2&last=v2` 返回 `v3,v4`。踩坑：Emo 没有字符串排序运算符——fake 用等值定位 `last` 再切片（通用情形由 SQL 处理）；T2.7 的未知路由示例恰好是 `/tags/list`，如今成了真路由。

#### T2.17 部署编排：Registry + MinIO + Caddy

**目标**：提供可重复部署：多阶段构建 Emo 二进制，运行镜像包含必要动态库；Compose 启动 Registry、MinIO、Caddy；配置卷、健康检查、TLS 与 `.env.example`。

**交付**：`deploy/Dockerfile`、`deploy/compose.yaml`、`deploy/Caddyfile`、`.env.example`、部署文档。

**验收**：干净机器上 `docker compose up -d` 后三个服务健康；Registry 通过 Caddy 访问；MinIO 数据持久化；重启后数据不丢；`.env.example` 不含真实密钥。

**依赖**：T2.6、T2.14 · **预估**：3h

> **备注**（2026-11-19，约 2.5h）：已完成，带一个环境限制说明。`deploy/` 包含整套栈：两阶段 `Dockerfile`（阶段 1 用 Emo 工具链编译 registry，`EMO_BUILDER_IMAGE` 构建参数指向携带 `emo` 的镜像——工具链尚年轻，发布构建镜像前可自备；阶段 2 为 `debian:bookworm-slim`，装 `libsqlite3-0`——c target 链接它——与 `wget` 供健康检查，非 root 用户，镜像级 HEALTHCHECK 打 /healthz）、`deploy/registry-entrypoint.sh`（PID 1 把 SIGTERM/SIGINT 转成服务器监听的 shutdown 标记文件——Emo 无信号处理——并等待排空）、`deploy/compose.yaml`（registry + MinIO + Caddy，内部网络，元数据/对象/证书的命名卷，MinIO 健康检查门控 registry 启动、registry 门控 Caddy，取值来自 `.env` 且四个密钥用 `:?` 拒绝缺省）、`deploy/Caddyfile`（单站点反代 registry，公网域名自动 Let's Encrypt / localhost 用内部 CA，缓存头原样透传）、`.env.example`（只有占位符，附生成提示）与 `docs/registry/deployment.md`。**宿主机已验证**：entrypoint 的信号协议端到端（SIGTERM → 标记 → 服务器的 `shutting down` / `stopped` 排空行 → 干净退出）——初版过早退出，因为被 trap 的信号会打断 shell 的 `wait`，重收尸改为循环等待服务器真正退出（提前退出会取消排空）；`docker compose config` 校验栈定义；核对二进制链接面（仅 `libsqlite3`）。**限制**：完整 `docker compose up` 无法在本机运行——MinIO 与 Caddy 镜像不可达（Docker Hub 经失效代理与配置的镜像站均超时；与 T2.6 的 S3 备注同一限制）。在有 registry 访问的机器上，`cd deploy && cp ../.env.example .env && docker compose up -d` 即为验证，T2.19 的冒烟脚本会在栈起来后端到端演练。

> **跟进**（2026-11-20，第 9 节验收时——代理已能访问 Docker Hub）：stack 的每一环都实际跑了一遍。发现并修掉定义里的两个真实 bug：服务端**必须有配置文件**（缺失即启动错误）——现为 `deploy/registry.compose.yaml`，只读挂载、不含密钥（环境变量在其上覆盖；`POKERFACE_REGISTRY_CONFIG` 指路）；auth 开启时**必须至少有一个账号**——现为 `deploy/registry.password`，挂载且 gitignored，由 `password_file` 引用。MinIO 的 healthcheck 改为 exec 形式（`CMD /usr/bin/curl …`），因为镜像里不保证有 shell。MinIO 本身用钉住的上游源码（`RELEASE.2025-04-22T22-12-26Z`）本地构建——MinIO 2025 年起不再发布社区镜像与二进制下载，`minio/minio:latest` 已不可得；本地镜像是 `FROM scratch` + 服务端二进制 + 一个极小的静态 curl。至此 MinIO healthy、registry 也接受了配置、账号与 S3 设置——然后 **Linux 版 registry 二进制在第一次 HTTP 交换时崩溃**：上游 Emo Linux c-runtime 缺陷（已二分：裸 `net` 原语、sqlite、runtime 核心在 Linux 上全部通过；任何活跃的 `http`/`httpd` 交换都会段错误）。证据与最小复现在 `docs/notes/runtime-capabilities.md`。stack 定义无需再改，卡点在上游。

#### T2.18 可观测性与审计

**目标**：补充结构化日志（`slog` JSON）、request id、访问日志、认证审计与 Prometheus 文本指标；避免记录 token、Authorization、预签名查询串。

**交付**：日志中间件、`/metrics`、审计事件、测试。

**验收**：每请求有 request id；日志可被 `jq` 解析；指标包含请求数、延迟、错误数、上传 / 下载字节数；认证失败有审计记录；敏感字段被脱敏。

**依赖**：T2.1 · **预估**：2-3h

#### T2.19 协议冒烟与一致性测试

> **备注**（2026-11-19，约 2.5h）：已完成。`registry/metrics.emo` + migration 3：计数器存 SQLite（`metrics(name, value)`），因为 httpd 一连接一进程——每个请求在**响应构建之后**用一个短事务以 UPSERT 累加自己的系列（数据库失败不会让已成功的请求失败），`/metrics` 渲染 Prometheus 文本格式：请求总数、错误数（4xx+5xx）、上传/下载字节、以及标准边界的延迟直方图（累计桶、`_sum` 以秒、`_count`）；全新存储渲染全零但完整的文档。路由器为每个请求输出一条 slog JSON 访问日志（ts、请求 id——与响应头 `X-Request-Id` 相同、方法、路径、状态、耗时、字节数；**绝不**记录查询串、请求头或 body，token 与预签名签名无从泄露），每次认证失败输出一条 `warn` 审计记录（`event=auth_failure` + 原因；原因描述状态而非凭据）。新增 `observability:` 配置段（access_log / metrics，默认开启），支持 `POKERFACE_REGISTRY_ACCESS_LOG` / `_METRICS` 环境变量覆盖、摘要开关与严格未知字段检查。`/metrics` 公开（只有计数）且仅 GET。metrics 沉淀为接口（`Sink`：record + render），解释器测试跑 fake，`DbSink` 走 sqlite3。测试：`test/registry_metrics.emo` 9 例（桶边界、路由分组、端点公开/文本/405 形态、逐请求记录、认证失败记录、配置默认/env/未知字段/摘要开关）+ db_selftest 13 项（跨 bump 的 UPSERT 累计、累计桶、秒形 sum、全新存储全零、每个桶边界齐全）；`emo test` 488/488，db selftest 135/135。实测：四个请求得到 `pokerface_requests_total 4` / `errors_total 2` / `download_bytes_total 96`，访问日志逐行可解析，开启认证的实例写出 `auth_failure` 审计记录。踩坑：又是 E3009——sqlite 相关路径（record 与 render）必须藏在 Sink 接口后解释器才能跑；`(R, …)` 错误槽静态为 String（与早前 gate 重构同一约束）；slog 的 `level_info`/`format_json` 是函数而非常量。

**目标**：用真实客户端验证 Registry：`oras` 或 `skopeo` 推送、`pokerface pull` 拉取、预签名 Blob 下载、认证负向用例；形成可重复的冒烟脚本。

**交付**：`scripts/e2e-m2.sh`、测试镜像 fixture、测试说明。

**验收**：脚本从干净环境启动 compose、完成 push / pull / 校验并清理；失败时输出可定位的日志；不访问 Docker Hub；覆盖 401、404、digest 不匹配等错误路径。

**依赖**：T2.1-T2.18 · **预估**：3h

> **备注**（2026-11-19，约 3h）：已完成。`scripts/e2e-m2.sh` 驱动**真实** registry 服务（fs 后端，每次运行全新临时目录，仅 127.0.0.1——不接触 Docker Hub）：skopeo 推送由 `test/fixtures/oci` 组装的镜像，按 tag 的 manifest 回读同时校验 `Docker-Content-Digest` 与**字节级一致**，tags list 断言字典序与精确的 `Link` 头，`/api/v1/resolve` 应答 digest + 平台，blob 缓存断言 digest ETag、immutable 策略与 304，负向集合覆盖未知 tag/blob（404）与 digest 不匹配推送（400），pokerface CLI 从本地 Git lock 解析并拉取导入到检测到的容器运行时，认证环节以开启认证的实例重启 registry——匿名读取被挑战、`skopeo login` + 推送成功、pull-only token 无法推送（挑战中带 `insufficient_scope`）。连续验证两遍（可重复），零残留进程与临时目录，`e2e-m1.sh` 并行通过。耗时较长的踩坑：服务器按设计忽略 SIGTERM，以信号停止会让运行器永远挂起——要走 shutdown 标记（entrypoint 的协议）；`curl -f` 把预期中的 401 挑战在 `set -e` 下变成 exit 22（抓响应头时不带 `-f`）；线上头以 CRLF 结尾，grep 行锚点需先去 CR；c 运行时的空闲 worker 进程持有管道——本脚本必须重定向到文件运行、绝不接管道（已写进文件头注释）。

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
| [x] | T4.1 | `pokerface build` 命令与构建计划 | T1.4、T1.5 | 2h |
| [x] | T4.2 | BuildKit / podman 构建适配 | T4.1 | 3-4h |
| [x] | T4.3 | Registry 推送：Blob + Manifest | T1.10、T2.12、T4.2 | 3h |
| [x] | T4.4 | lock 文件生成与写回 | T4.3 | 2h |
| [x] | T4.5 | 构建触发与版本策略 ADR | 无 | 1h |
| [x] | T4.6 | CI 模板：GitHub Actions 为主 | T4.3、T4.4 | 3h |
| [x] | T4.7 | 安装脚本与发布工作流 | T1.1 | 3h |
| [x] | T4.8 | 文档站骨架与导航 | T4.5 | 2-3h |
| [x] | T4.9 | 快速开始与安装文档 | T4.7、T4.8 | 2h |
| [x] | T4.10 | CLI 与配置参考 | T1.1、T1.8 | 2h |
| [x] | T4.11 | YAML / lock / 元数据规范 | T1.4、T1.5 | 3h |
| [x] | T4.12 | Registry 运维指南 | T2.17 | 3h |
| [x] | T4.13 | 示例应用 | T4.2、T4.3 | 3h |
| [x] | T4.14 | 端到端演示脚本 | T4.3、T4.13、T1.14 | 3h |
| [x] | T4.15 | 故障回退与排障矩阵 | T1.14、T2.19 | 2h |
| [x] | T4.16 | README、中文版与发布清单 | T4.8-T4.15 | 2h |
| [x] | T4.17 | CI 端到端回归 | T4.14 | 3h |

### 6.3 任务详情

#### T4.1 `pokerface build` 命令与构建计划

**目标**：读取 `pokerface.yaml`，校验配置与上下文，解析 tag 模板，生成构建计划并以 `--dry-run` 展示：镜像名、tag 列表、平台、构建参数、Dockerfile、上下文。

**交付**：`src/commands/build.emo`、tag 渲染器、dry-run 测试。

**验收**：示例配置输出稳定；缺 Dockerfile / 上下文不存在 / tag 重复时报错；`--dry-run` 不执行任何构建或网络请求；支持 `--platform` 覆盖。

**依赖**：T1.4、T1.5 · **预估**：2h

> **笔记**（2026-11-19，约 2.5h）：完成。`src/build.emo` 承载计划模型（`GitMetadata`、`BuildPlan`）、tag 渲染器（手扫 `{{`/`}}`——`String.index_of` 不带起始下标）、碰撞检查（两条不同模板渲染出同一字符串即碰撞，错误同时给出两个位置：`tags[1] ('{{ git.tag }}') collides with tags[0]`）、Git 事实采集（rev-parse/describe 在**上下文目录**里跑；exact-match describe 失败 = 非 tag 触发，记 `""`），以及带共享 `context_dir` 解析的 `plan()`（相对配置文件目录解析；`.` 上下文拼接成 `/.` 后去尾）。`src/commands/build.emo` 的组合是读 → 解析（`src.config.load`——这是**构建**配置，绝不走 `src.settings.load`，后者会按客户端 config.yaml 的未知字段拒绝它）→ 上下文检查 → Git 采集 → 计划 → Dockerfile 检查 → 打印；拆出 `compose_plan` + `plan_text`（T1.14 resolve 的先例），测试直接断言 `print_plan` println 的原行，不需要拦截 stdout。发现规则：`--config` > `./pokerface.yaml`（cwd；`os.getcwd()` 返回裸 String）。空渲染（未打 tag 构建上的单独 `{{ git.tag }}`）统一走字符集检查——一种拒绝形状，"renders to an invalid tag"。不带 `--dry-run` 在 T4.2 前是用法错误。路由踩坑：`route()` 对除 pull/cache 外的任何命令都直接拒绝未知 `--` 选项，`build --dry-run` 根本到不了命令——build 已加入按命令解析名单。验证：12 个测试（渲染/碰撞/元数据/计划/命令），`emo test` 500/500，c target 编译通过，编译产物端到端驱动（cwd 发现、`--config`、`--json`、`--platform` 覆盖、退出码 2/1）。规范：`docs/spec/build-plan.md`。后续：T4.2 消费 `BuildPlan`；T4.10 并入 CLI 参考。

#### T4.2 BuildKit / podman 构建适配

**目标**：封装本地构建工具。优先 Docker BuildKit `buildx build --output type=oci`；podman 作为备选。写入 OCI 标准标签：`org.opencontainers.image.revision`、`source`、`version`、`created`。

**交付**：`src/build.emo`、工具检测、日志流式输出、构建测试。

**验收**：示例 Dockerfile 可构建为 OCI Layout；镜像 inspect 能看到 commit / source 标签；构建失败返回原始日志与退出码；无 BuildKit 时给出清晰提示；多平台构建作为可选能力，失败不影响单平台。

**依赖**：T4.1 · **预估**：3-4h

> **笔记**（2026-11-20，约 3h）：完成。`src/build.emo` 扩展出适配器：`detect_tool`（优先 buildx docker——`docker buildx version`——其次 podman；都没有 → `runtime: no build tool found`，退出码 8）、`buildx_argv`（一次 `buildx build` 调用：平台一次传入、每个 tag 一个 `--tag` 使 index.json 每个标签一条描述符、`--provenance=false --sbom=false` 保持布局只含请求的 manifest、`--output=type=oci,dest=<work>/build.tar`、context 最后）、`podman_argv` + save（`podman build --format=oci`，再 `podman save --format=oci-dir`——只带第一个 tag，push 补齐其余），以及 `execute()`（docker：buildx tar + `tar -xf`；布局先经 `src.oci.validate` + `read_index` 校验再作答）。`RealStreamRunner` fork 时继承 stdout/stderr，构建日志实时流出（与 git 的 RealRunner 同款双 fork 看门狗；只回传退出码，`pokerface: build: 'docker' exited with code 1` 垫在原始日志下面）。`GitMetadata` 增加完整 SHA（rev-parse HEAD，short 派生——c target 拒绝在 init 里条件赋值字段，所以 commit_short 仍是 init 参数）和 origin URL（source 标签，无 origin 时省略）。`created` 注入 execute()（命令传 `rfc3339_now()`，测试传定值——保证 fake 的 argv 钉子确定）。工作目录：`<TMPDIR>/pokerface-build-<pid>/`。`pokerface build`（不带 --dry-run）现在会组合、检查、执行并报告 tool/layout/digests/tags。本机真机验证（docker buildx v0.38.1、daemon 29.9.3）：FROM scratch 仓库离线构建出通过校验的布局；`skopeo inspect --config` 显示 `revision` = 完整 SHA、`source` = origin、`created` = RFC3339；digest 与 CLI 报告一致；坏 Dockerfile 会先流出 buildx 的 ERROR 块再退出 1；`--platform linux/amd64,linux/arm64` 产出干净的 2-manifest 索引。Podman 路径仅 fake 测试——本机未装 podman（T2.17 同款保留项）。测试：新增 10 个（检测 ×3、argv 形状 ×3、rfc3339、execute docker/podman/失败——fake 背后用真实 fixture 组装的布局）；`emo test` 510/510，c target 编译通过。踩坑：e2e 管道挂起再次命中——CLI 的 stdout 接管道会因空闲调度 worker 卡死（重定向到文件，e2e-m2.sh 已有记载）；错误信息里出现 "timeout" 一词会被归类成 network（已改写成 "limit"）。规范：docs/spec/build-plan.md "Execution (T4.2)"。

#### T4.3 Registry 推送：Blob + Manifest

**目标**：复用 M1 的 Registry 客户端，实现 Blob 上传（单块 / 分块）、Manifest 推送、tag 更新、digest 捕获与重试。

**交付**：`src/push.emo`、推送测试、进度输出。

**验收**：推送到 M2 Registry 成功；返回的 digest 与本地一致；重复推送可跳过已存在 Blob；中途失败可重试且不破坏已有 tag；认证 scope 正确。

**依赖**：T1.10、T2.12、T4.2 · **预估**：3h

> **笔记**（2026-11-20，约 4h）：完成。`src/push.emo` 是完整管线：拆镜像（复用 pull 的 `split_image`——镜像 host 即端点，loopback 走 http、其余 https）→ 客户端 probe → blob HEAD（200 即跳过，一个字节都不读）→ 上传（4 MiB 以下单请求 `POST ?digest=`；以上走会话分块 PATCH，Content-Range 用规范的裸区间）→ 按 digest 推 manifest → 打 tag。两个发现决定了形状。**HEAD 缺口**：std http 客户端把 HEAD 响应声明的 Content-Length 当 body 读，直接死于 "closed after 0 of N bytes"——registry 的 HEAD 应答完全符合规范，于是 HEAD 走独立传输（`HeadTransport` + `RealHeadTransport`：基于 `net` 的 HTTP/1.1、只读到响应头，复用 blob.emo 的 URL 解析与响应头读取；可注入测试）。**子 manifest 是 manifest 而不只是 blob**：M2 的 index 校验对 MANIFESTS 表查子项，而真实客户端在推 index 之前会按 digest PUT 子 manifest——所以布局里每个描述符都以 `/manifests/<digest>` 推出（对 buildx 的嵌套多平台包装递归处理），buildx 每个 `--tag` 一条描述符的 index.json 按 digest 去重，tag 目标在单平台布局时指向 manifest、其余指向 index。registry 应答的 `Docker-Content-Digest` 必须等于推送字节的本地 sha256（不符即 integrity 退出码 7）；传输错误与 5xx 重试 3 次；401 以 `repository:<repo>:pull,push` 作用域重跳并重放一次。进度通过 `Progress` 接口实时流出（`--json` 用 `SilentProgress` 保持 stdout 只有一份报告）。`pokerface build` 在 pokerface.yaml 有 `registry` 节时自动推送（token 来自 `POKERFACE_REGISTRY_TOKEN`/配置——`--config` 指的是构建文件而非客户端配置，settings.load 不带 flag 加载）。registry 侧：`/api/v1/resolve` 的平台遍历递归嵌套 index（深度 4），无平台的 manifest 子项从其 config 取平台——buildx 包装层不再回答空平台。**对真实 registry 端到端验证**：单平台推送 digest == 服务端 `Docker-Content-Digest` == skopeo 读回；重复推送跳过确定性 layer；多平台推送服务端是干净的 2 平台 index 且 resolve 回答两个平台；auth 场景：铸造的 push 作用域 token 推送成功，pull-only token 被 registry 自己的错误信封拒绝（退出码 5），无 token 时 dance 失败清晰可读；`e2e-m2.sh` 依旧通过。测试：`test/push.emo` 新增 9 个（RecTransport + RecHeadTransport，规则带调用预算）+ resolve 嵌套 index 2 个；`emo test` 519/519，c target 编译通过。已知后续：客户端的 Basic 用户名密码换 token（当前 token 由外部提供）；解释器的六元组深嵌套与 manifest 的 `Subject` 字段未动。规范：docs/spec/push.md；build-plan.md 的执行节已更新。

#### T4.4 lock 文件生成与写回

**目标**：构建推送成功后生成 `pokerface.lock.yaml`，记录 commit、镜像、tags、digest、平台、builder；支持 `--write-lock`，可选 `--commit` 只做本地 Git 提交，不自动 push。

**交付**：lock 生成器、合并逻辑、测试。

**验收**：重复构建同一镜像时 lock 幂等；多 tag、多平台条目稳定排序；不覆盖无关条目；不写入真实密钥；`pokerface resolve` 能直接消费生成的 lock。

**依赖**：T4.3 · **预估**：2h

> **笔记**（2026-11-20，约 2h）：完成。`src/lockfile.emo` 长出生成侧：`entry_for`（tags/platforms 按字典序排序——Emo 字符串没有顺序运算符，`text_less` 经排序字符集逐字节比较；digest 用加载器自己的规则校验）、`merge`（同名 image 的条目**原位替换**，缺失的追加，无关条目原样保留，`generated_at` 强制为空使相同输入编码出相同字节），以及 `fresh_doc`。`pokerface build --write-lock` 在推送成功后把 `pokerface.lock.yaml` 写到 pokerface.yaml 旁边（必须有 registry 节——lock 记录的是推送后的 digest）：`commit` = 构建所用的完整 SHA，`source` = origin 远端经加载器 `parse_source` 归一化（无 origin 的仓库直接报错——source 是必填），`builder` = buildkit/podman 按适配器工具映射。已有 lock 走合并；解析不了的 lock 报错而不是静默覆盖。`--commit` 只把 lock 这一个文件做本地提交（`git add --` + `git commit -- pokerface.lock.yaml`，提交信息 `pokerface: update pokerface.lock.yaml`——pathspec 提交，其他已暂存/已修改文件绝不搭车）且从不推送；`--commit` 不带 `--write-lock` 是用法错误。无密钥：schema 里没有承载凭据的字段。对真实 registry 端到端验证：写出的 lock 形状（排序的 tags/platforms、builder 行、无关条目保留、第二次运行原位替换）、lock 提交只动 `pokerface.lock.yaml`，以及 `pokerface resolve <repo>:main` 直接从提交里消费 lock 得到镜像+digest。幂等性说明：lock 的**形状**跨重建稳定（`test_rebuild_is_idempotent` 钉住 encode/load/merge 循环），但 digest 每次构建都会变——buildx 会盖 `created` 时间戳，已在规范中如实注明而不是粉饰。测试：`test/lockfile.emo` 新增 6 个；`emo test` 525/525，c target 编译通过。规范：pokerface-lock.md "Generation (T4.4)" + build-plan.md "Lock write-back"。

#### T4.5 构建触发与版本策略 ADR

**目标**：明确 v0.1 的构建触发方式：由 Git push / tag / CI `workflow_dispatch` 触发，不实现自建 webhook 服务；定义 tag 规则（默认分支 `latest`、Git tag 原样、commit 短 SHA、语义化版本）。

**交付**：`docs/adr/0001-build-trigger.md`、版本策略文档。

**验收**：决策记录包含背景、备选方案与取舍；CI 模板与 tag 规则一致；文档明确“轮询 / 自建 webhook”留到后续版本。

**依赖**：无 · **预估**：1h

> **笔记**（2026-11-20，约 1h）：完成。`docs/adr/0001-build-trigger.md` 以标准 ADR 形状（背景/决策/备选/后果/延后）记录 D7。**触发器**：恰好三个 CI 事件——分支推送、tag 推送、`workflow_dispatch`；各自映射到 T4.1 渲染器消费的 Git 事实。**Tag 规则**：所有构建都有 `sha-{{ commit.short }}`；默认分支有 `latest`；`{{ branch }}` 只用于能通过 OCI 字符集的分支名（`feat/x` 会被渲染器大声拒绝——如实记录而非静默改写）；Git tag 原样使用；`{{ version }}` 来自 `git describe --tags --abbrev=0`。**Semver 策略**：`vX.Y.Z` 原样推送；浮动便利 tag（`1.2`、`1`、由 semver 驱动的 `latest`）明确**延后**——那是带真实爆炸半径的 registry 变更策略，值得单独一份 ADR。**版本策略**（独立小节）：版本号 = 最近可达 tag，发布纪律 = 打 tag → 推送 → tag 触发构建 → lock，lock 是"某个 tag 在某个 commit 上是什么意思"的唯一事实来源，重建即新构建（buildx 会盖 `created`）。**否决项**：自建 webhook 服务（第二个常驻服务，重复 CI 已有的机制——只有在需要无 CI 的分钟级构建时才重启讨论）与轮询（浪费构建、限速、延迟，什么也换不来）。**写明的后果**：v0.1 没有构建队列/日志/状态——resolve 回答*构建了什么*，从不回答*正在构建什么*；契约是纯 Git 的，任何能在 checkout 上跑二进制的 CI 都能构建，服务端无需安装任何东西。版本策略以 ADR 的独立小节存在（T4.11 并入规范集）。纯文档改动——代码路径不变；`emo test` 525/525 不变，规范索引已链接 ADR。

#### T4.6 CI 模板：GitHub Actions 为主

**目标**：提供可复用 workflow：checkout、安装 pokerface、登录 Registry、`pokerface build --push --write-lock`、提交 lock 回仓库。补充 GitLab CI / Gitea Actions 的最小示例。

**交付**：`.github/workflows/publish.yaml`、`docs/ci/github-actions.md`、GitLab / Gitea 示例。

**验收**：workflow 通过 `actionlint`；示例仓库能跑通；提交 lock 使用 `[skip ci]` 或路径过滤避免循环；secrets 不落盘；权限最小化。

**依赖**：T4.3、T4.4 · **预估**：3h

> **笔记**（2026-11-20，约 2h）：完成。`.github/workflows/publish.yaml` 实现 ADR 0001 的触发契约（分支推送、`v*` tag、`workflow_dispatch`）：`fetch-depth: 0` 的 checkout（渲染器要的 Git 事实）、固定版本的安装步骤（T4.7 的脚本，`POKERFACE_VERSION` 环境变量）、`pokerface build --write-lock`（推送由 registry 节驱动——没有会忘掉的 `--push` 旗标，这是对任务原文的有意偏差，已记录在 build-plan.md），以及只在 lock 变化时才提交回推的步骤，提交信息 `pokerface: update pokerface.lock.yaml [skip ci]`。**防循环双保险**：push 的 `paths-ignore: pokerface.lock.yaml` 加上提交信息里的 `[skip ci]`——任一都够用，两个都带上是因为模板被人改坏一份时不该变成无限构建循环。**权限最小化**：只给 `contents: write`——registry 用自己的 `POKERFACE_REGISTRY_TOKEN` secret 认证，从不用 GitHub 的；token 以步骤级环境变量进 CLI，绝不落盘（lock 的 schema 没有凭据字段）。**本仓库内的安全**：工作流在本仓库空转——步骤级 `hashFiles('pokerface.yaml') != ''` 守卫——actionlint v1.7.7 抓到 `hashFiles` 在 JOB 级不合法（报错正是 "calling function hashFiles is not allowed here"），这就是守卫放在步骤上的原因；`actionlint .github/workflows/publish.yaml` 通过（二进制取到 /tmp，不做全局安装）。GitLab（`.gitlab-ci.yml` 示例，dind、branch/tag/web 三种 rules、掩码+保护变量）与 Gitea（同形工作流；其防循环靠 paths-ignore，因为 `[skip ci]` 的支持取决于实例版本）在 `docs/ci/gitlab-ci.md` 与 `docs/ci/gitea-actions.md`；`docs/ci/github-actions.md` 是逐步说明。**主机上能验的都验了**：工作流的 commit-back 步骤在仿真里**逐字**跑过（本地仓库 + bare 远端 + 真实 registry）：首次运行以准确的信息提交并推送 lock，空暂存路径干净地空转，重复运行行为一致，`git log` 里 lock 提交都带 `[skip ci]`；"示例仓库跑通"仍是需要真实 GitHub 的检查（留给 T4.17 的回归）。值得记住的 YAML 坑：`tags: [latest, sha-{{ commit.short }}]` 解析失败——`{{` 会在流序列里打开流映射；模板条目要加引号。规范索引已链接 docs/ci/。

#### T4.7 安装脚本与发布工作流

**目标**：提供 `install.sh` 与发布流程：识别 OS / 架构、下载对应二进制、校验 checksum、安装到 `PATH`；发布 workflow 交叉编译 Linux / macOS 的 amd64 / arm64 产物。

**交付**：`install.sh`、`.github/workflows/release.yaml`、checksum 文件、安装文档。

**验收**：干净容器中 `curl ... | sh` 安装成功；`pokerface version` 与发布版本一致；checksum 不匹配时拒绝安装；脚本不使用不安全的临时文件权限。

**依赖**：T1.1 · **预估**：3h

> **笔记**（2026-11-20，约 2h）：完成。`install.sh`（仓库根，POSIX sh——验收的 `curl … | sh` 在 dash 下也能跑）：OS/架构检测映射到发布矩阵（darwin/linux × amd64/arm64），从 GitHub release 下载 `pokerface-<platform>.tar.gz` + `checksums.txt`（版本 = `POKERFACE_VERSION` 钉住，或 latest-release 重定向——不走 API、无速率限制），**写任何东西之前先校验 sha256**（不符 → 退出码 1，什么都不安装），把 0755 的二进制装进 `~/.local/bin`（`POKERFACE_INSTALL_DIR` 可覆盖），打印 PATH 提示但绝不改 shell 配置，产物只经过一个 chmod 700 的 `mktemp -d` 目录并带 EXIT trap。可覆盖项：版本、安装目录、`POKERFACE_DOWNLOAD_BASE`（镜像站——也是没有真实 release 时测试脚本的入口）。`.github/workflows/release.yaml` 在每个 `v*` tag 上发版：四个 runner **原生**构建（ubuntu-latest、ubuntu-24.04-arm、macos-latest、macos-13——不交叉编译、不模拟），按平台打包 `pokerface + registry` 并附各平台 `.sha256` 与合并的 `checksums.txt`，`gh release create --verify-tag --generate-notes` 发布。最重的一步是 Emo 工具链（opam 钉编译器仓库），与 deploy/Dockerfile 同款如实注明：builder 镜像发布后会变成一条 `docker run`。macOS/Linux runner 为 registry 二进制装 libsqlite3（CLI 只链 libc）。两个工作流都过 actionlint v1.7.7。**主机上验证**：`file://` 供给的假 release（真实二进制、真实 tar、真实校验和）——快乐路径安装两个 0755 二进制且 `pokerface version` 回答 `0.1.0`；损坏的产物对原始校验和以退出码 1 中止且零安装（第一次失配测试是自证循环——我给损坏文件重新生成了校验和——已用正确方式重做）。`docs/install.md` 覆盖一行安装、覆盖项表、手工校验、发布管线与源码构建。版本备注：二进制的 `version` 字符串是 T1.1 的常量（`0.1.0`），tag↔二进制可能漂移——版本号注入是 T4.16 发布清单的候选跟进项。

#### T4.8 文档站骨架与导航

**目标**：建立文档站：Getting Started、CLI、Configuration、Spec、Registry、Examples、Troubleshooting。优先纯 Markdown + GitHub Pages；需要搜索时再引入 VitePress。

**交付**：`docs-site/` 或 `docs/` 站点配置、导航、首页、部署 workflow。

**验收**：本地可预览；导航无死链；移动端可读；部署到 GitHub Pages 成功；文档源文件仍在 `docs/` 便于 review。

**依赖**：T4.5 · **预估**：2-3h

> **笔记**（2026-11-20，约 2h）：完成，按决策 D10——GitHub Pages 上的纯 Markdown，无框架、无 node_modules。`docs-site/build.py`（python3 + `markdown` 包，唯一依赖）把 docs/ 下所有 .md 经一个模板渲染进 `docs-site/site/`：固定侧栏（Getting started / Reference / Specifications / Registry / Project）、标题取每页首个一级标题、viewport meta 与 ≤900px 媒体查询保证移动端可读、导航 URL 按页面深度取相对路径（项目 Pages 挂在子路径下）。**死链会让构建失败**：构建器把每条相对 markdown 链接（和每个导航项）对着 docs 树解析，出错即退出 1 并列出问题——导航不会悄悄烂掉（立刻见效：导航先写了 quick-start.md 而该页还不存在，构建直接拒绝）。正文里兄弟页面的 `.md` 链接在构建时改写成 `.html`。`docs-site/preview.sh` 构建并在 127.0.0.1:8080 伺服——用真实 HTTP 验证（首页与 spec/push.html 的标题正确、/install.html 返回 200）。`.github/workflows/docs.yaml` 在触碰 docs/** 的推送上部署（setup-python、pip install markdown、构建、upload-pages-artifact + deploy-pages，权限 `pages: write`/`id-token: write`，concurrency 取消旧跑）；actionlint 通过。源 Markdown 留在 docs/ 原样可审——构建器只读。`docs-site/site/` 已 gitignore。"部署到 GitHub Pages 成功"是需要真实 GitHub 的检查（记给 T4.17）。导航的 quick-start 项随 T4.9 落地。

#### T4.9 快速开始与安装文档

**目标**：让新用户在 10 分钟内完成：安装、`pokerface resolve`、`pokerface pull`、`docker run`。明确前置依赖：Git、skopeo、Docker / podman。

**交付**：`docs/getting-started.md`、可复制命令、预期输出、常见失败提示。

**验收**：按文档在干净环境执行成功；命令与当前 CLI 一致；中文版关键段落同步；明确说明不依赖 Docker Hub。

**依赖**：T4.7、T4.8 · **预估**：2h

> **笔记**（2026-11-20，约 1.5h）：完成。`docs/getting-started.md` + 中文镜像（`getting-started.zh-CN.md`——验收要求的"关键节中文对照"），都已接入站点导航（死链检查器现在会守护它们）。流程：前置条件表（Git / skopeo / Docker-or-podman，注明没有 skopeo 时会怎样）→ 安装 → **五行启动本地 registry**（`registry.yaml` 用 `$HOME` 路径——服务端配置不展开波浪号）→ 带 pokerface.yaml 和 origin 远端的应用仓库（lock 的 `source` 需要它——跑指南时踩出来的）→ `pokerface build --write-lock` 附真实输出形状 → 提交 lock → `resolve .:main` → `pull` → `docker image inspect`。**开篇即声明"Docker Hub 不是必需"**，且结构上成立：`FROM scratch`、loopback registry、零外部拉取。常见错误提示是四条一行式并指向 T4.15 的矩阵。**跑指南跑出来的两处修正**：(1) 最终检查改为 `docker image inspect`——初稿用 `docker run … cat /hello.txt`，而 FROM scratch 镜像里没有 `cat`（实测失败后改稿；可运行版本留给 examples/app，T4.13）；(2) `resolve` 只有在 lock 提交之后才工作——指南的顺序把这一点写明了。每条命令都对真实二进制逐字执行过（build 以 source `github.com/you/quick-app` 写出 lock、resolve 回答推送的 digest、pull 导入 docker）；唯一没法在本机测的是发布包安装本身（T4.7 的 file:// 仿真覆盖了它）。工具链记录：验证脚本把 `pokerface build` 管道给了 `tail`——空闲调度器管道挂起再现，指南正文本身无管道。

#### T4.10 CLI 与配置参考

**目标**：为所有命令、参数、环境变量、配置文件字段、退出码建立参考文档，并尽量从 `--help` 输出生成或校验。

**交付**：`docs/reference/cli.md`、`docs/reference/config.md`、帮助文本快照测试。

**验收**：文档覆盖所有命令；参数默认值准确；退出码与 `docs/spec/errors.md` 一致；CI 检查帮助文本变更时提醒更新文档。

**依赖**：T1.1、T1.8 · **预估**：2h

> **笔记**（2026-11-20，约 2h）：完成。`docs/reference/cli.md` 记录完整命令面——build 已是**实现状态**（四个选项与 T4.1–T4.4 的链路；config 如实标注 stub），全局旗标（附 build 场景下 --config 指**构建文件**的警告）、退出码表对齐 docs/spec/errors.md（build 新增：runtime 8 覆盖"无构建工具"，integrity 7 覆盖服务端 digest 不符）、引用语法、各命令行为与真实输出形状。`docs/reference/config.md` 覆盖优先级、客户端配置文件（registry.url/token、cache_dir）、六个环境变量——用 `grep POKERFACE_ src/settings.emo` 核对过（恰好六个，一个不多）；客户端 `POKERFACE_*` 与服务端 `POKERFACE_REGISTRY_*` 两族明确分家，密钥脱敏行为如实记录，"v0.1 不可配置项"清单不含糊（无构建工具覆盖项、超时固定）。`docs/cli.md` 改为重定向桩，旧链接不断。**快照测试**：`test_help_text_snapshot_matches_the_reference` 钉住 help 文本的命令顺序、build 描述行、每个全局旗标与 `-h, --help`——失败即表示参考页要同一次改动里更新（测试注释就写明了）；emo test 526/526。**CI 警告**：docs.yaml 增加漂移检查（grep 路由表的命令标签 vs 参考页的命令清单，未记录即 `::warning`），且 src/cli.emo 加入该工作流的 paths 过滤——help 文本变更真的会触发它；本机已验证（routed 与 documented 集合干净相交）。站点重建：43 页，链接全部通过；两个工作流过 actionlint。

#### T4.11 YAML / lock / 元数据规范

**目标**：把 `pokerface.yaml`、`pokerface.lock.yaml` 与 Manifest 元数据整理成正式规范：字段、类型、校验规则、版本兼容策略、示例、与 OCI 字段的映射。

**交付**：`docs/spec/pokerface-yaml.md`、`docs/spec/pokerface-lock.md`、JSON Schema（可选但推荐）、示例。

**验收**：所有示例通过 Schema 校验；规范覆盖未知字段 / 版本升级策略；与实现中的校验一致；review 无歧义。

**依赖**：T1.4、T1.5 · **预估**：3h

> **笔记**（2026-11-20，约 2h）：完成。两份规范在 T1.4/T1.5/T4.1/T4.4 时已带完整字段表；T4.11 做了形式化。**JSON Schema**（推荐交付物）：`docs/schema/pokerface-yaml.schema.json` 与 `pokerface-lock.schema.json`——draft 2020-12，`version` 用 `const 1`，每层 `additionalProperties: false`，image/source/commit/digest/tag/platform 形状用正则钉住，每个 schema 的 description 写明 schema 语言**无法表达**的跨字段规则（yaml 的重复 tag 与渲染碰撞；lock 的镜像名唯一与 generated_at 不参与校验——评审的主要产出就是把这条边界写明）。`docs/schema/validate.py` 把 `examples/pokerface.yaml` 与 `examples/pokerface.lock.yaml` 对着 schema 校验（draft-2020-12，jsonschema 4.25、pyyaml 6.0.3）——**2 个示例全部通过**，并接入 docs 工作流，示例与 schema 的漂移会让构建失败。**版本兼容**：两份规范写明严格相等规则（只认 version 1）、升级策略（未来版本必须继续读 version 1；放宽只随版本号变更，绝不悄悄打补丁）、以及 schema 与实现的分工。**OCI 映射**：表格把每个配置/lock 字段映射到 OCI 落点——image → 仓库路径、渲染后的 tags → tag PUT/描述符、platforms → index 的 platform 对象、args/target → 构建器旗标**绝不是**镜像元数据；labels 表（revision/source/version/created）指向 T4.2；lock 的 digest/manifest_digest/platforms 对应 resolve API 的回答。builder 字段只是构建元数据，不是 OCI 字段。评审确认字段表与实现一致（默认值：dockerfile Dockerfile、platforms [linux/amd64]、tags [latest]；字符集规则；未知字段路径）——除 schema 限制的说明外未发现歧义。站点重建（43 页），emo test 526/526 不变（纯文档）。

#### T4.12 Registry 运维指南

**目标**：面向自建 Registry 的运维者：Compose 部署、S3/MinIO 配置、CDN 接入、TLS、认证、备份、Blob 清理、容量与监控、安全清单。

**交付**：`docs/registry/operations.md`、部署示例、故障排查清单。

**验收**：按文档可从零部署；CDN 缓存策略与代码一致；备份 / 恢复步骤可执行；包含“不要暴露 MinIO 凭据”的安全提醒。

**依赖**：T2.17 · **预估**：3h

> **笔记**（2026-11-20，约 2h）：完成。`docs/registry/operations.md` 是运维手册，内容对着真实的配置面写（对照 registry/config.emo 的严格未知字段清单核实：listen/data_dir/db_path/store{fs,s3}/limits/shutdown_file/auth/observability；s3 有 presign_ttl 与 verify_tls；limits 有 max_body_bytes 默认 16 MiB）。小节：**拓扑**（compose 见 deployment.md；裸二进制与停机协议）、**存储**（fs 原子改名语义；S3 启动桶检查；presigned 307 重定向）、**认证**（D6 的预共享账号、signing key 轮换立即失效、反代头纪律保证 Bearer dance）、**TLS**（Caddy LE 与 localhost 内部 CA、Host 头透传）、**缓存**（CDN 表与 registry-cache.md 完全一致——blob 永久不可变、manifest 60 秒 must-revalidate、/token 与 /metrics 永不缓存、307 不可吞掉）、**备份/恢复**（可执行的停→拷→起，用停机标记文件、/readyz 门禁、SQLite+桶必须成对一致的警告、digest 比对式恢复验证）、**容量与清理**（上传会话过期自动清理；孤儿 blob 会累积——v0.1 没有 GC，如实写明——附一条只读 SQL 审计查询，已对着真实的 manifests/blobs 表结构核实，删除明确写成停机后的手动操作）、**监控**（/healthz 与 /readyz 的语义差别、指标序列、抓取片段、无泄漏的日志契约），以及**安全清单**——首条即验收要求的警告：MinIO 绝不对外暴露——拿到桶和密钥的人可以绕过 registry 做的一切认证检查。排障指向 T4.15。站点导航加入 runbook；重建 44 页，链接全部通过。

#### T4.13 示例应用

**目标**：提供一个最小示例：Dockerfile + `pokerface.yaml` + 一个可访问的 HTTP 服务；用于演示 Git 元数据、构建、推送与拉取。

**交付**：`examples/hello/`、示例 README、预期镜像大小与启动命令。

**验收**：`pokerface build --push --write-lock` 成功；`pokerface pull` 后容器返回 200；镜像不含构建缓存与密钥；示例可作为 CI 模板的输入。

**依赖**：T4.2、T4.3 · **预估**：3h

> **笔记**（2026-11-20，约 3h，含一个 P0 发现）：完成。`examples/hello/`：纯标准库的 Go 服务（`/` 返回 200 与消息、`/healthz` 返回 `ok`）、两个提交进仓库的静态 Linux 二进制（CGO off、`-trimpath -ldflags "-s -w"`——镜像是 `FROM scratch` + 一个二进制，无 shell、无构建缓存、无密钥）、使用 buildx 的 `ARG TARGETARCH` 的 Dockerfile（README 记录了重建命令），以及双平台 `pokerface.yaml`。**本任务挖出一个 P0 级 runtime 限制并交付了绕过方案**：c runtime 的 plain-TCP `send` 把 EAGAIN（socket 缓冲区满）当致命错误——任何超过约 64 KiB 的单个响应体都会中途断流，对所有客户端都一样（实测：curl 只取回 2,516,528 字节 blob 中的 326,812 字节；registry 的一次性 httpd 响应写和客户端的大 body 上传都会踩中）。绕过方案全部在本仓库内：push 以 64 KiB 的 PATCH 窗口上传；registry 的 blob GET 服务有界 206 窗口（`blob_range_window` 32 KiB，Content-Range 精确标注所发切片，越界 416、非法 Range 400）；pull 下载器走窗口（与声明大小的不足量从 `.meta` 偏移继续，直到达到大小再做 digest 校验；无进展的窗口报错）。根因与建议的 runtime 修复（EAGAIN 时等待可写，与 TLS 路径一致，改 emo_c_runtime.c + 解释器）记录在 `docs/notes/runtime-capabilities.md`，留给 emo-lang 项目——在它落地前，所有客户端对大 blob 的普通 200 GET 都会中途断流。**端到端验证**在形如 CI 目标的独立仓库（examples/hello 拷出、`git init`、origin 远端——决策 D2 把 lock 放在仓库**根目录**，所以子目录里的示例无法从父仓库解析）：`build --write-lock` 推出双平台 index（5 uploaded、2 skipped——相同二进制的 layer 被跳过）、`resolve` 回答推送的 digest、`pull` 走 206 窗口导入 docker、运行容器后 `curl` 返回 **HTTP/1.1 200 OK** 且 `/healthz` 为 `ok`；预期大小每平台 8.4 MB（静态 Go 二进制）。测试：新增 5 个 Range 窗口路由测试；emo test 531/531，c target 编译通过。客户端同步修复：`select_platform` 递归嵌套 index（registry 侧 resolve 修复的客户端孪生版），repo 参数贯穿。踩坑：`pokerface.yaml` 流式 `tags: [latest, sha-{{ … }}]` 解析失败（模板条目要加引号）；`ARG TARGETARCH` 必须先声明再使用；子目录里的 lock 对 resolve 不可见（D2 的根目录规则是真实契约）。

#### T4.14 端到端演示脚本

**目标**：一条命令演示完整链路：启动本地 Registry / MinIO、构建示例、推送、写 lock、`resolve`、`pull`、运行容器并断言 HTTP 响应。

**交付**：`scripts/e2e.sh`、`--ci` 模式、日志与清理逻辑。

**验收**：干净机器上一条命令成功；失败时保留诊断日志；不访问 Docker Hub；耗时在可接受范围（目标 10 分钟内）；重复执行不污染环境。

**依赖**：T4.3、T4.13、T1.14 · **预估**：3h

> **笔记**（2026-11-20，约 1.5h）：完成。`scripts/e2e.sh` 一条命令走完 M4 全路径：emo 构建两个二进制 → 本地 fs registry 起在 `127.0.0.1:$PORT`（`E2E_PORT`，默认 4598）以 `/healthz` 把门 → examples/hello 拷进全新 git 仓库，**pokerface.yaml 由脚本生成**（示例里提交的配置指向快速开始的端口——首次运行把镜像推到了 4599 上的旧 registry，而 docker run 找的是 4598；生成 yaml 使镜像与 registry 一致）→ `build --write-lock`（buildx 日志落文件）→ 提交 lock → `resolve` 对着 lock 的 digest 断言 → `pull` → 容器运行（docker、podman 兜底）并 `curl` 断言 **200 + hello 正文 + /healthz ok** → 重复构建断言相同 layer 被跳过。`--ci` 模式保留全部断言但只打印一行 `[e2e] 步骤`。**验证两次**（常规 14 秒、--ci 13 秒——远低于 10 分钟目标）；失败保留临时目录与各步骤日志并打印路径；成功运行零残留（唯一一次失败运行的目录已按删除规则移走）。结构上无 Docker Hub（FROM scratch + loopback）。工具链坑再次确认：跑它要重定向到文件，绝不进管道。脚本还会用停机标记清理残留 registry——而 data_dir 被删掉的 registry 无法走标记协议（标记写不进去），那个孤儿只能 SIGKILL，记给 T4.15。

#### T4.15 故障回退与排障矩阵

**目标**：把 README 中的失败回退写成可执行文档，并逐项验证：Git 失败、Manifest 失败、CDN 失败、digest 不匹配、运行时导入失败、缓存损坏。

**交付**：`docs/troubleshooting.md`、回退矩阵、诊断命令、测试记录。

**验收**：每个场景都有“现象 / 原因 / 处理 / 验证”四段；文档行为与实现一致；包含离线模式与缓存清理步骤。

**依赖**：T1.14、T2.19 · **预估**：2h

> **笔记**（2026-11-20，约 1.5h）：完成。`docs/troubleshooting.md`——十三个场景，每个都有要求的**症状/原因/处理/验证**四节，页首是症状→退出码→场景的速查表。除了任务点名的 README 回退项（Git 失败、manifest 失败、CDN 失败、digest 不符、运行时导入、缓存损坏），还覆盖了 M4 真正教给我们的：无构建工具（8）、构建失败浮出 buildx 日志（1）、tag 渲染与碰撞（4）、lock 写回规则（缺 origin、旧 lock 解析失败）、认证的作用域 dance 与 Basic 凭据边界、**大文件传输**（64 KiB socket 写限制、窗口协议、以及"runtime 修复落地前其他客户端拉大 blob 仍会断"的如实说明）、**停止 registry**（标记协议；SIGTERM 设计上被忽略；T4.14 清理时的孤儿进程 SIGKILL 案例）。离线模式与缓存清理各有独立处理条目（`--offline` 需要完整缓存；verify 默认修复、rm 重置）。每条验证都指向钉住该行为的测试或执行过的运行——文档行为与实现按构造一致（每个场景都写自本会话的真实观察，而非想象）。站点导航加入 Troubleshooting；重建 45 页，链接全部通过。

#### T4.16 README、中文版与发布清单

**目标**：更新 README 的项目状态、Quick Start、Roadmap 勾选与链接；同步 `README.zh-CN.md`；建立发布清单（版本号、changelog、tag、安装脚本、回滚）。

**交付**：更新后的 `README.md` / `README.zh-CN.md`、`RELEASE.md`、`CHANGELOG.md`。

**验收**：英文与中文内容一一对应；命令可复制执行；Roadmap 勾选与实际一致；发布清单覆盖版本号与 tag 规则；无过期截图或链接。

**依赖**：T4.8-T4.15 · **预估**：2h

> **笔记**（2026-11-20，约 1.5h）：完成。`README.md` / `README.zh-CN.md` 一一对应更新：项目状态段（M1+M2+M4 已实现，带日期与文档链接）、与真实 CLI 一致的快速开始（`curl … | sh` 安装 → 本地 registry → `pokerface build --write-lock` + lock 提交 → `resolve`/`pull`/`docker run`）、一条命令验证块（三个 e2e 脚本）、路线图复选框改为真实状态（7/7 打勾并带任务编号；v0.1 之后的诚实清单：浮动 semver tag、Basic 换 token、registry GC、runtime socket 写修复）。过时的"build 属于后续里程碑"与虚构的 `build --repo … --push` 示例已删除。`RELEASE.md` 是发布清单：版本号与改动同提交的规则、changelog 纪律、打 tag 前的门禁（全量测试、双构建、三个 e2e 脚本、文档站构建、actionlint）、annotated `v*` tag 触发与 release.yaml 的产物、发布后对真实校验和的安装验证、回滚语义（修正版最新发布即回滚；registry 绝不跨迁移回滚）。`CHANGELOG.md` 覆盖 0.1.0，按里程碑分组，并点名两个修复（Range 窗口、嵌套 index 递归）。中英命令在 T4.9/T4.13/T4.14 的真实运行中验证过可复制粘贴；无截图可过期；每个链接目标都存在（文档站死链检查器通过）。

#### T4.17 CI 端到端回归

**目标**：在 CI 中定期运行端到端链路，防止 Registry / CLI / 构建脚本的回归。支持手动触发与每日定时。

**交付**：`.github/workflows/e2e.yaml`、缓存策略、失败日志 artifact。

**验收**：CI 在主干通过；耗时控制在 15 分钟内；失败时能下载 compose 日志与 CLI 日志；E2E 运行阶段不访问 Docker Hub；构建所需基础镜像提前缓存或使用本地镜像，并在 workflow 中固定来源。

**依赖**：T4.14 · **预估**：3h

> **笔记**（2026-11-20，约 1h）：完成。`.github/workflows/e2e.yaml`：三个 e2e 脚本（m1 客户端链路、m2 registry 协议、m4 构建交付的 `--ci` 模式）在触碰代码的推送（main+develop）、每日 02:23 UTC 与手动触发时运行。**工具链缓存**：`~/.opam` 以固定 emo-lang commit 为键（`EMO_REF` 环境变量——安装步骤钉同一个 SHA，重建可复现；即验收要求的"源钉死"）；命中缓存则跳过安装只设 PATH。**无 Docker Hub、无基础镜像**：所有镜像 FROM scratch 并由脚本自起的本地 registry 供源——没有需要预缓存的镜像，工作流头注明。**预算**：timeout-minutes 15；本地脚本 13–14 秒，冷工具链约 10 分钟（之后有缓存）。**失败日志**：每个脚本的 stdout 重定向到 /tmp/e2e-*.out（失败时回显进任务日志），脚本失败时保留带分步日志的临时目录，`failure()` 门控的 upload-artifact 收集 /tmp/e2e-*.out 与 /tmp/pokerface-e2e*/。**顺带**：e2e 之后跑 `emo test`。actionlint 通过；**三个脚本在最终树上全部验证绿色**（m1 ok、m2 ok、m4 PASS 13s）。"main 分支 CI 通过"是需要真实 GitHub 运行的一项——工作流已按此塑形。

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

2026-11-20 按实现后的真实接口逐项核实（每行标注证据位置）；唯一未勾项是本机无法完成的 compose/MinIO 运行时声明（Docker Hub 不可达——恰是 pokerface 要绕开的问题；stack 定义与入口协议已验证，见 docs/registry/deployment.md）。

- [x] `pokerface resolve` 能输出 `tag -> commit -> digest`。（e2e-m1/m2/m4 断言 digest 行）
- [x] `pokerface pull` 能完成下载、校验、导入，`docker run` / `podman run` 正常。（T4.13/T4.14 实测：容器返回 HTTP 200）
- [x] 拉取过程不访问 `registry-1.docker.io`。（结构使然——FROM scratch + loopback；e2e 脚本据此断言）
- [ ] Registry 可通过 compose 一键启动，MinIO 数据持久化。*（2026-11-20：stack 定义已修正，且每一环都实际跑到了——MinIO 由钉住的上游源码构建并 healthy、registry 接受了挂载的配置与 auth 账号、exec 形式 healthcheck——但 Linux 版 registry 二进制在第一次 HTTP 交换时崩溃：上游 Emo Linux runtime 缺陷，二分证据记录在 `docs/notes/runtime-capabilities.md`。顺带修了两个 stack bug：服务端必须有配置文件（现为 `deploy/registry.compose.yaml`，挂载）与至少一个 auth 账号（现为 `deploy/registry.password`，挂载、gitignored）。卡在上游，不在本仓库。）*
- [x] Manifest / Blob / Tag 的 OCI 必要接口可用，`oras` 或 `skopeo` 冒烟通过。（e2e-m2：真实 skopeo 推送、读回、auth 场景）
- [x] Blob 通过预签名 URL 下载，过期后失效。（test/registry_s3.emo：预签名 GET 200，TTL 过期后 403；fs 后端直接供源）
- [x] pull / push scope 生效，越权请求被拒绝。（e2e-m2 auth 场景：pull-only token 无法 push、`insufficient_scope` challenge）
- [x] `pokerface build --write-lock` 可完成构建、推送与元数据写回。*（清单原文的 `--push` 旗标落地为配置的 `registry` 节——docs/spec/build-plan.md；e2e.sh 断言推送与 lock）*
- [x] CI 模板可用，且不会产生提交循环。（T4.6：actionlint 通过、commit-back 步骤逐字仿真、paths-ignore + `[skip ci]`；真实 GitHub 运行归 T4.17）
- [x] 示例应用可通过 `scripts/e2e.sh` 一键演示。（T4.14：13–14 秒，两次，零残留）
- [x] 文档站包含安装、快速开始、CLI、规范、Registry 运维与排障。（45 页，死链使构建失败）
- [x] README 英文与中文版本同步，Roadmap 与实际状态一致。（T4.16，一一对应）
