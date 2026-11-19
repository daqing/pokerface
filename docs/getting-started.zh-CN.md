# 快速开始

> 英文版：[getting-started.md](getting-started.md)。十分钟、五组命令。
> **不需要 Docker Hub**——本指南的任何一步都不会连接 Docker Hub 或任何
> 外部 registry；镜像从零构建，由本机上的 registry 供源。

## 前置条件

| 工具 | 用途 | 检查 |
| --- | --- | --- |
| Git | 解析链读取 Git | `git --version` |
| skopeo | 把拉取的镜像导入本地运行时 | `skopeo --version` |
| Docker 或 podman | 最后运行镜像 | `docker info` |
| C 编译工具链 | 仅当从源码构建而不安装发布包时需要 | `cc --version` |

skopeo 负责运行时导入（`docs/spec/runtime-import.md`）；没有它时
`pokerface pull` 会完成全部校验，然后以清晰的错误停止。

## 1. 安装

```console
$ curl -fsSL https://raw.githubusercontent.com/daqing/pokerface/main/install.sh | sh
$ pokerface version
pokerface 0.1.0
```

（钉版本、安装前缀与手工校验见 `docs/install.md`。）

## 2. 启动本地 registry

```console
$ mkdir -p "$HOME/pokerface-quick/data" "$HOME/pokerface-quick/blobs"
$ cat > "$HOME/pokerface-quick/registry.yaml" <<EOF
listen:
  host: 127.0.0.1
  port: 4599
data_dir: $HOME/pokerface-quick/data
store:
  backend: fs
  root: $HOME/pokerface-quick/blobs
EOF
$ registry --config "$HOME/pokerface-quick/registry.yaml" &
$ curl -s http://127.0.0.1:4599/healthz
ok
```

完整的配置面（认证、S3、限额）在 `docs/spec/registry-config.md`；停止它
用 `<data_dir>/registry.shutdown` 标记文件——服务器设计上忽略 SIGTERM。

## 3. 一个应用仓库

```console
$ git init -b main quick-app && cd quick-app
$ printf 'FROM scratch\nCOPY hello.txt /hello.txt\n' > Dockerfile
$ printf 'hello from pokerface\n' > hello.txt
$ cat > pokerface.yaml <<'EOF'
version: 1
image: 127.0.0.1:4599/quick/app
build:
  context: "."
  dockerfile: Dockerfile
  platforms: [linux/amd64]
tags:
  - latest
  - "sha-{{ commit.short }}"
registry:
  url: http://127.0.0.1:4599
EOF
$ git add . && git commit -m "quick app"
$ git remote add origin git@github.com:you/quick-app.git
```

`image` 命名镜像将存放的位置（`<host>/<owner>/<repo>`）；`registry` 表示
这个仓库要推送。tag 规则见 ADR 0001（`docs/adr/0001-build-trigger.md`）。

## 4. 构建、推送并写回 lock

```console
$ pokerface build --write-lock
tool:       docker
digest:     sha256:833f… (application/vnd.oci.image.manifest.v1+json)
tags:       latest, sha-9cf4c848
pushed:     127.0.0.1:4599/quick/app (3 uploaded, 0 skipped)
lock:       /path/to/quick-app/pokerface.lock.yaml
```

这一行之前流出的内容是 buildx 自己的日志。提交 lock：

```console
$ git add pokerface.lock.yaml && git commit -m "pokerface: update lock"
```

## 5. 解析与拉取

```console
$ pokerface resolve .:main
ref:     /path/to/quick-app:main
commit:  9cf4c848…
image:   127.0.0.1:4599/quick/app
digest:  sha256:833f…
tags:    latest, sha-9cf4c848
```

```console
$ pokerface pull .:main
platform: linux/amd64
runtime:  docker (127.0.0.1:4599/quick/app:latest)
$ docker image inspect 127.0.0.1:4599/quick/app:latest --format '{{.Os}}/{{.Architecture}}'
linux/amd64
```

`pull` 从 registry 拉取 manifest 与 blob，逐个校验 digest，再经 skopeo
把镜像导入你的运行时——运行时看到的名字是
`127.0.0.1:4599/quick/app:latest`。（`FROM scratch` 的镜像里没有 shell，
要在容器里执行得等镜像里有可执行内容；示例应用 `examples/app/` 给出一个
可运行的版本。）

## 出错时

- **`git: cannot read the commit`**——上下文目录不是 Git 仓库；每个构建都
  从某个 commit 构建。
- **`renders to an invalid tag`**——模板渲染出了 OCI tag 字符集之外的
  字符（带 `/` 的分支名、未打 tag 仓库上的 `{{ version }}`）。
- **`runtime: skopeo is required`**——安装 skopeo，或读
  `docs/spec/pull.md` 了解没有它时 pull 的行为。
- **registry `connection refused`**——registry 没在运行，或
  `pokerface.yaml` 里 `registry.url` 的端口与 `listen` 不一致。
- 完整矩阵见 `docs/troubleshooting.md`（T4.15）。

## 下一步

- 每次推送自动发布：`docs/ci/github-actions.md`。
- 正经部署 registry（TLS、MinIO、compose）：`docs/registry/deployment.md`。
- 准确的 CLI 面：`docs/cli.md`。
