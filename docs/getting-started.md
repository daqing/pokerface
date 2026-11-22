# Quick Start

> Chinese mirror: [getting-started.zh-CN.md](getting-started.zh-CN.md).
> Ten minutes, five commands. **Docker Hub is not required** — nothing in
> this guide contacts Docker Hub or any external registry; the image is
> built from scratch and served by a registry running on your machine.

## Prerequisites

| Tool | Why | Check |
| --- | --- | --- |
| Git | the resolution chain reads Git | `git --version` |
| skopeo | imports the pulled image into your runtime | `skopeo --version` |
| Docker or podman | runs the image at the end | `docker info` |
| A C compiler toolchain | only if you build from source instead of installing | `cc --version` |

skopeo does the runtime import (`docs/spec/runtime-import.md`); without it
`pokerface pull` verifies everything and then stops with a clear message.

## 1. Install

```console
$ curl -fsSL https://raw.githubusercontent.com/daqing/pokerface/main/install.sh | sh
$ pokerface version
pokerface 0.1.0
```

(`docs/install.md` — pins, prefixes, and manual verification.)

## 2. Start a local registry

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
$ pokerface-registry --config "$HOME/pokerface-quick/registry.yaml" &
$ curl -s http://127.0.0.1:4599/healthz
ok
```

The full configuration surface (auth, S3, limits) is
`docs/spec/registry-config.md`; stop it by touching
`<data_dir>/registry.shutdown` — the server ignores SIGTERM by design.

## 3. An application repository

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

The origin remote names the repository in the lock's `source` field (the
next step writes it); any Git URL form works.

`image` names where the image will live (`<host>/<owner>/<repo>`);
`registry` says this repository wants pushing. The tag rules are ADR 0001's
(`docs/adr/0001-build-trigger.md`).

## 4. Build, push, and write the lock

```console
$ pokerface build --write-lock
tool:       docker
digest:     sha256:833f… (application/vnd.oci.image.manifest.v1+json)
tags:       latest, sha-9cf4c848
pushed:     127.0.0.1:4599/quick/app (3 uploaded, 0 skipped)
lock:       /path/to/quick-app/pokerface.lock.yaml
```

The streamed lines above this are buildx's own log. Commit the lock:

```console
$ git add pokerface.lock.yaml && git commit -m "pokerface: update lock"
```

## 5. Resolve and pull

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
$ docker image inspect 127.0.0.1:4599/quick/app:latest --format '{{.Os}}/{{.Architecture}} {{.Size}} bytes'
linux/amd64 1234567 bytes
```

`pull` fetches the manifest and blobs from the registry, verifies every
digest, and imports the image into your runtime via skopeo — the runtime
sees it as `127.0.0.1:4599/quick/app:latest`. (A `FROM scratch` image
carries no shell, so `docker run` it only after it has something to
execute; the example application — `examples/app/` — shows a runnable one.)

## If something goes wrong

- **`git: cannot read the commit`** — the context directory is not a Git
  repository; every build is built from a commit.
- **`renders to an invalid tag`** — a template produced characters outside
  the OCI tag charset (a branch with a `/` in it, an untagged `{{ version }}`).
- **`runtime: skopeo is required`** — install skopeo, or read
  `docs/spec/pull.md` for what pull does without it.
- **`connection refused` on the registry** — it is not running, or the
  port in `pokerface.yaml`'s `registry.url` does not match `listen`.
- The full matrix lives in `docs/troubleshooting.md` (T4.15).

## What is next

- Publish automatically on every push: `docs/ci/github-actions.md`.
- Run the registry for real (TLS, MinIO, compose): `docs/registry/deployment.md`.
- The exact CLI surface: `docs/cli.md`.
