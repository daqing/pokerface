# PokerFace

一个基于 Git 远程仓库分发容器镜像的开源 Docker 替代品。

Git 管元数据与构建上下文，CDN/对象存储管二进制层，`pokerface` 负责把两者粘合起来，并提供**抗屏蔽的镜像拉取能力**——全程不向 `registry-1.docker.io` 发起 `docker pull`，从架构上规避 TLS timeout。



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

> M1 客户端（`resolve`、`pull`、`cache`、`version`）已实现；`build` 属于后续里程碑。

```bash
# 拉取镜像（从 Git 元数据解析，经 CDN 下载，导入本地 Docker）
pokerface pull github.com/you/app:latest

# 查看解析结果（tag → Commit → Digest）
pokerface resolve github.com/you/app:latest

# 构建并推送（后续里程碑）
pokerface build --repo github.com/you/app --push
```

### M1 客户端示例

```console
$ pokerface resolve github.com/acme/app:latest
ref:     github.com/acme/app:latest
commit:  c1e0a12d02ba5efbdd3d5ac6358ee1b7f12b079e
image:   registry.example.com/acme/app
digest:  sha256:720e8b95ef5c4ccb7b71101986481029202e7d5ecd9e644fdd089590ff9cf131
tags:    latest

$ pokerface pull github.com/acme/app:latest
image:    registry.example.com/acme/app:latest
digest:   sha256:720e8b95ef5c4ccb7b71101986481029202e7d5ecd9e644fdd089590ff9cf131
commit:   c1e0a12d02ba5efbdd3d5ac6358ee1b7f12b079e
platform: linux/amd64
runtime:  docker (registry.example.com/acme/app:latest)

$ pokerface cache ls
cache: /Users/you/.cache/pokerface
  git        1 entries  27.4 KiB
  manifests  1 entries  805 B
  blobs      2 entries  363 B
  refs       1 entries  41 B
  total      5 entries  28.6 KiB
  limits     ttl=(unset) max_size=(unset)
```

首次在线拉取后，`pokerface pull <ref> --offline` 可完全从本地缓存重复拉取。`pokerface cache verify` 校验缓存并淘汰损坏条目；`pokerface cache rm` 清空缓存。M1 流程规范见 `docs/spec/pull.md` 与 `docs/spec/cache.md`。

完全本地的验证（fixture Git 仓库 + Emo mock registry/CDN，不访问 Docker Hub）：

```bash
./scripts/e2e-m1.sh
```

脚本会构建 CLI，执行 resolve/pull、离线二次拉取与缓存命令，并在 skopeo 加 docker/podman/ctr 可用时导入检测到的运行时。设置 `KEEP_TMP=1` 可保留临时目录与日志。

## 设计要点

- **Git 只存元数据**：Dockerfile、`pokerface.yaml`（构建参数、tag 规则、目标 Registry）与应用代码同源，镜像层二进制不进 Git。
- **Blob 内容寻址，CDN 长缓存**：镜像层按 Digest 不可变，适合 CDN 长期缓存；Manifest 会随 Tag 变化，采用短缓存或回源。
- **认证与鉴权分离**：Registry 签发短期预签名 URL 或 Token，避免 Blob 公开裸奔。
- **兼容 OCI Distribution Spec**：对外暴露 `/v2/` 接口，Manifest 中 Blob 地址指向 CDN，标准客户端理论上也可识别。
- **抗屏蔽拉取**：`pokerface pull` 全程走你控制的域名/CDN，不触发对 `registry-1.docker.io` 的请求；底层可调用 `skopeo` 或内置 HTTP 客户端完成下载与导入。

## 路线图

- [x] CLI 骨架与 `pokerface.yaml` 规范定义
- [x] Git 元数据解析（tag → Commit → Digest）
- [ ] Registry/元数据服务最小实现（Manifest + 预签名 URL）
- [ ] CDN/对象存储后端对接（S3/MinIO 兼容）
- [x] `skopeo` 集成与本地运行时导入
- [ ] 构建触发器与 CI 模板
- [ ] 文档站与端到端示例

## 贡献

欢迎 Issue 与 PR。提交前请阅读 `CONTRIBUTING.md`，并确保新增功能附带测试与文档更新。

## 许可证

MIT

## Translation

[English](README.md)
