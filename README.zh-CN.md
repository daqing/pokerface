# PokerFace

一个基于 Git 远程仓库分发容器镜像的开源 Docker 替代品。

Git 管元数据与构建上下文，CDN/对象存储管二进制层，`pokerface` 负责把两者粘合起来，并提供**抗屏蔽的镜像拉取能力**——全程不向 `registry-1.docker.io` 发起 `docker pull`，从架构上规避 TLS timeout。

**状态**（2026-11-20）：客户端链路（M1）、registry 服务（M2）与构建交付链路（M4）均已实现——`pokerface build` 用 buildx 或 podman 构建、推送并写回 lock；registry 提供 OCI distribution 子集、fs/S3(MinIO) 存储、Bearer 认证、指标与 compose 部署。文档：[快速开始](docs/getting-started.zh-CN.md) · [CLI 参考](docs/reference/cli.md) · [规范索引](docs/spec/README.md) · [排障矩阵](docs/troubleshooting.md)。



## 为什么做这个项目

- **Git 原生溯源**：镜像的构建配方（Dockerfile、构建参数、目标 tag）与应用代码同源管理，任何镜像都能回溯到确切的 Git Commit。
- **不把二进制塞进 Git**：镜像层走 CDN/对象存储，Git 仓库保持轻量。
- **抗屏蔽拉取**：用户通过 `pokerface pull` 从你控制的域名/CDN 拉取镜像并导入本地运行时，不依赖被干扰的 Docker Hub。
- **兼容现有运行时**：最终镜像导入 Docker / containerd / podman，日常 `docker run` / `podman run` 不受影响。

## 架构

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│                              开发者 / CI 构建侧                                │
│                                                                              │
│   ┌─────────────────────┐        git push        ┌─────────────────────┐    │
│   │  应用代码仓库        │ ─────────────────────▶ │  Git 远程仓库        │    │
│   │  Dockerfile         │                        │  (GitHub/GitLab/    │    │
│   │  pokerface.yaml     │                        │   自建 Gitea)        │    │
│   │  (构建元数据/清单)   │                        │                     │    │
│   └─────────────────────┘                        └──────────┬──────────┘    │
│                                                             │ webhook/轮询   │
│                                                             ▼               │
│                                                  ┌─────────────────────┐    │
│                                                  │  构建触发器 / CI     │    │
│                                                  │  (读取 Git 元数据)   │    │
│                                                  └──────────┬──────────┘    │
│                                                             │ 构建镜像       │
│                                                             ▼               │
│                                                  ┌─────────────────────┐    │
│                                                  │  镜像构建器          │    │
│                                                  │  (BuildKit/         │    │
│                                                  │   podman build)     │    │
│                                                  └──────────┬──────────┘    │
└─────────────────────────────────────────────────────────────┼───────────────┘
                                                              │ push manifest + blobs
                                                              ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│                           分发层（你控制的基础设施）                           │
│                                                                              │
│   ┌──────────────────────────────────────────────────────────────────────┐  │
│   │                    OCI 兼容 Registry / 元数据服务                      │  │
│   │  ┌────────────────────────┐      ┌────────────────────────────────┐  │  │
│   │  │ Manifest / Tag 管理     │      │ 认证与鉴权 (Token / 预签名)     │  │  │
│   │  │ (轻量动态服务，可回源)   │      │ 签发 CDN 短期访问凭证           │  │  │
│   │  └───────────┬────────────┘      └────────────────────────────────┘  │  │
│   │              │ 返回 Manifest（其中 Blob 地址指向 CDN）                  │  │
│   └──────────────┼───────────────────────────────────────────────────────┘  │
│                  │                                                          │
│                  ▼                                                          │
│   ┌──────────────────────────────────────────────────────────────────────┐  │
│   │                         CDN / 对象存储                                │  │
│   │   ┌──────────────┐  ┌──────────────┐  ┌──────────────┐              │  │
│   │   │  Blob (Layer)│  │  Blob (Layer)│  │  Blob (Layer)│  ...         │  │
│   │   │  按 Digest    │  │  按 Digest    │  │  按 Digest    │              │  │
│   │   │  内容寻址     │  │  内容寻址     │  │  内容寻址     │              │  │
│   │   └──────────────┘  └──────────────┘  └──────────────┘              │  │
│   │   特性：不可变 Blob 长缓存；Manifest 短缓存/回源；支持预签名 URL        │  │
│   └──────────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────────┘
                                      ▲
                                      │ HTTPS（走你控制的域名/CDN，非 Docker Hub）
                                      │
┌─────────────────────────────────────┼────────────────────────────────────────┐
│                          用户侧（抗屏蔽拉取）                                 │
│                                     │                                        │
│   ┌─────────────────────────────────┴────────────────────────────────────┐   │
│   │                         pokerface CLI                                │   │
│   │  1. 读取 Git 元数据，解析 tag → Commit SHA → 镜像 Digest              │   │
│   │  2. 向 Registry 请求 Manifest（获取 Blob 的 CDN 地址/预签名 URL）      │   │
│   │  3. 调用 skopeo / 内置 HTTP 客户端，从 CDN 下载 Blob                  │   │
│   │  4. 校验 Digest，导入本地容器运行时                                    │   │
│   └─────────────────────────────────┬────────────────────────────────────┘   │
│                                     │                                        │
│                                     ▼                                        │
│   ┌──────────────────────────────────────────────────────────────────────┐  │
│   │              本地容器运行时（Docker / containerd / podman）            │  │
│   │              镜像已导入，可直接 docker run / podman run               │  │
│   └──────────────────────────────────────────────────────────────────────┘  │
│                                                                              │
│   注：全程不向 registry-1.docker.io 发起 docker pull，规避 TLS timeout       │
└──────────────────────────────────────────────────────────────────────────────┘
```

## 拉取时序

```text
用户            pokerface CLI        Git 远程仓库       Registry/元数据服务        CDN/对象存储        本地容器运行时
 │                   │                    │                    │                    │                    │
 │ pokerface pull    │                    │                    │                    │                    │
 │ repo:tag          │                    │                    │                    │                    │
 ├──────────────────▶│                    │                    │                    │                    │
 │                   │                    │                    │                    │                    │
 │                   │ 1. 解析 tag→Commit │                    │                    │                    │
 │                   ├───────────────────▶│                    │                    │                    │
 │                   │◀───────────────────┤                    │                    │                    │
 │                   │   Commit SHA       │                    │                    │                    │
 │                   │                    │                    │                    │                    │
 │                   │ 2. 读取元数据，得到镜像 Digest           │                    │                    │
 │                   ├───────────────────▶│                    │                    │                    │
 │                   │◀───────────────────┤                    │                    │                    │
 │                   │   Digest           │                    │                    │                    │
 │                   │                    │                    │                    │                    │
 │                   │ 3. 请求 Manifest   │                    │                    │                    │
 │                   ├────────────────────┼───────────────────▶│                    │                    │
 │                   │                    │                    │ 返回 Manifest      │                    │
 │                   │                    │                    │ (Blob→CDN URL/     │                    │
 │                   │◀───────────────────┼────────────────────┤  预签名 URL)       │                    │
 │                   │                    │                    │                    │                    │
 │                   │ 4. 下载 Blob (HTTPS，走 CDN 域名)        │                    │                    │
 │                   ├────────────────────┼────────────────────┼───────────────────▶│                    │
 │                   │◀───────────────────┼────────────────────┼────────────────────┤                    │
 │                   │   Blob 数据流       │                    │                    │                    │
 │                   │                    │                    │                    │                    │
 │                   │ 5. 校验 Digest     │                    │                    │                    │
 │                   │ 6. 导入本地运行时   │                    │                    │                    │
 │                   ├────────────────────┼────────────────────┼────────────────────┼───────────────────▶│
 │                   │                    │                    │                    │                    │
 │◀──────────────────┤ 完成               │                    │                    │                    │
 │                   │                    │                    │                    │                    │
```

失败回退：Git 解析失败直接报错；Manifest 请求失败回退到经过校验的本地缓存；Blob 下载失败按 Blob 重试并校验 Digest；导入失败清理临时文件。已实现的行为见 [docs/spec/pull.md](docs/spec/pull.md)。

## 快速开始

安装（或从源码构建——见 `docs/install.md`）：

```bash
curl -fsSL https://raw.githubusercontent.com/daqing/pokerface/main/install.sh | sh
pokerface version
```

整条链路在本地即可跑通，不需要 Docker Hub——本机起 registry，镜像 `FROM scratch`：

```bash
# 启动本地 registry（生产部署见 docs/registry/operations.md）
pokerface-registry --config registry.yaml &

# 在应用仓库里（docs/getting-started.zh-CN.md 有完整 walkthrough）：
pokerface build --write-lock     # buildx 构建、pokerface 推送、lock 记录 digest
git add pokerface.lock.yaml && git commit -m "pokerface: update lock"

# 任何地方消费：
pokerface resolve github.com/you/app:main    # tag → commit → digest
pokerface pull github.com/you/app:main       # 校验并导入 Docker/podman
docker run --rm 127.0.0.1:4599/hello/app:latest
```

带预期输出的完整 walkthrough 在
[docs/getting-started.zh-CN.md](docs/getting-started.zh-CN.md)（英文:
[docs/getting-started.md](docs/getting-started.md)）；完整命令面在
[docs/reference/cli.md](docs/reference/cli.md)。

### 一条命令验证整条链路

```bash
./scripts/e2e.sh          # M4 演示：build → push → lock → resolve → pull → HTTP 200
./scripts/e2e-m2.sh       # M2 registry：skopeo 推送、协议边界、认证
./scripts/e2e-m1.sh       # M1 客户端：resolve/pull/离线/缓存
```

每个脚本都会构建二进制、对本地 registry 运行并断言各步骤；失败保留分步日志。`pokerface cache verify` 校验并修复缓存；`pokerface cache rm` 清空。各流程规范见 `docs/spec/pull.md`、`docs/spec/build-plan.md`、`docs/spec/push.md` 与 `docs/spec/cache.md`。

## 设计要点

- **Git 只存元数据**：Dockerfile、`pokerface.yaml`（构建参数、tag 规则、目标 Registry）与应用代码同源，镜像层二进制不进 Git。
- **Blob 内容寻址，CDN 长缓存**：镜像层按 Digest 不可变，适合 CDN 长期缓存；Manifest 会随 Tag 变化，采用短缓存或回源。
- **认证与鉴权分离**：Registry 签发短期预签名 URL 或 Token，避免 Blob 公开裸奔。
- **兼容 OCI Distribution Spec**：对外暴露 `/v2/` 接口，Manifest 中 Blob 地址指向 CDN，标准客户端理论上也可识别。
- **抗屏蔽拉取**：`pokerface pull` 全程走你控制的域名/CDN，不触发对 `registry-1.docker.io` 的请求；底层可调用 `skopeo` 或内置 HTTP 客户端完成下载与导入。

## 路线图

- [x] CLI 骨架与 `pokerface.yaml` 规范定义（T1.1、T1.4）
- [x] Git 元数据解析（tag → Commit → Digest）（T1.6–T1.9）
- [x] Registry/元数据服务最小实现（Manifest + 预签名 URL）（M2：T2.1–T2.19）
- [x] CDN/对象存储后端对接（S3/MinIO 兼容）（T2.4–T2.6）
- [x] `skopeo` 集成与本地运行时导入（T1.13）
- [x] 构建触发器与 CI 模板（M4：T4.1–T4.7，ADR 0001）
- [x] 文档站与端到端示例（T4.8–T4.15）
- [ ] v0.1 之后：浮动 semver tag、Basic 凭据换 token、registry 垃圾回收、runtime socket 写修复（`docs/notes/runtime-capabilities.md`）

## 贡献

欢迎 Issue 与 PR。提交前请阅读 `CONTRIBUTING.md`，并确保新增功能附带测试与文档更新。

## 许可证

MIT

## Translation

[English](README.md)
