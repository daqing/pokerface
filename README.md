# PokerFace

An open-source Docker alternative that distributes container images via Git remote repositories.

Git manages metadata and build context, CDN/object storage manages binary layers, and `pokerface` glues them together. It provides **censorship-resistant image pulling**—no `docker pull` request ever hits `registry-1.docker.io`, eliminating TLS timeouts by design.

**Status** (2026-11-20): the client loop (M1), the registry service (M2),
and the build-and-delivery path (M4) are implemented — `pokerface build`
builds with buildx or podman, pushes to the registry, and writes the lock
CI consumes; the registry serves the OCI distribution subset with fs or
S3/MinIO storage, Bearer auth, metrics, and a compose deployment. Docs:
[getting started](docs/getting-started.md) ·
[CLI reference](docs/reference/cli.md) ·
[specs](docs/spec/README.md) ·
[troubleshooting](docs/troubleshooting.md).



## Why PokerFace

- **Git-native traceability**: Image build recipes (Dockerfile, build args, target tags) live alongside application code. Every image traces back to an exact Git commit.
- **No binaries in Git**: Image layers go to CDN/object storage, keeping Git repositories lightweight.
- **Censorship-resistant pulling**: Users run `pokerface pull` to fetch images from domains/CDNs you control and import them into the local runtime—no dependency on a interfered Docker Hub.
- **Runtime compatibility**: Final images are imported into Docker / containerd / podman. Daily `docker run` / `podman run` workflows remain unchanged.

## Architecture

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│                          Developer / CI Build Side                            │
│                                                                              │
│   ┌─────────────────────┐        git push        ┌─────────────────────┐    │
│   │  App Code Repo      │ ─────────────────────▶ │  Git Remote         │    │
│   │  Dockerfile         │                        │  (GitHub/GitLab/    │    │
│   │  pokerface.yaml     │                        │   self-hosted Gitea)│    │
│   │  (build metadata)   │                        │                     │    │
│   └─────────────────────┘                        └──────────┬──────────┘    │
│                                                             │ webhook/poll   │
│                                                             ▼               │
│                                                  ┌─────────────────────┐    │
│                                                  │  Build Trigger / CI │    │
│                                                  │  (reads Git meta)   │    │
│                                                  └──────────┬──────────┘    │
│                                                             │ build image    │
│                                                             ▼               │
│                                                  ┌─────────────────────┐    │
│                                                  │  Image Builder      │    │
│                                                  │  (BuildKit/         │    │
│                                                  │   podman build)     │    │
│                                                  └──────────┬──────────┘    │
└─────────────────────────────────────────────────────────────┼───────────────┘
                                                              │ push manifest + blobs
                                                              ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│                       Distribution Layer (infra you control)                  │
│                                                                              │
│   ┌──────────────────────────────────────────────────────────────────────┐  │
│   │                    OCI-compatible Registry / Metadata Service         │  │
│   │  ┌────────────────────────┐      ┌────────────────────────────────┐  │  │
│   │  │ Manifest / Tag Mgmt    │      │ Auth & Authorization           │  │  │
│   │  │ (lightweight dynamic   │      │ (Token / presigned URL)        │  │  │
│   │  │  service, can fallback)│      │ issues short-lived CDN creds   │  │  │
│   │  └───────────┬────────────┘      └────────────────────────────────┘  │  │
│   │              │ returns Manifest (Blob URLs point to CDN)               │  │
│   └──────────────┼───────────────────────────────────────────────────────┘  │
│                  │                                                          │
│                  ▼                                                          │
│   ┌──────────────────────────────────────────────────────────────────────┐  │
│   │                         CDN / Object Storage                          │  │
│   │   ┌──────────────┐  ┌──────────────┐  ┌──────────────┐              │  │
│   │   │  Blob (Layer)│  │  Blob (Layer)│  │  Blob (Layer)│  ...         │  │
│   │   │  content-    │  │  content-    │  │  content-    │              │  │
│   │   │  addressed   │  │  addressed   │  │  addressed   │              │  │
│   │   └──────────────┘  └──────────────┘  └──────────────┘              │  │
│   │   Immutable blobs long-cached; Manifests short-cached/fallback;       │  │
│   │   presigned URLs supported                                           │  │
│   └──────────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────────┘
                                      ▲
                                      │ HTTPS (your domain/CDN, not Docker Hub)
                                      │
┌─────────────────────────────────────┼────────────────────────────────────────┐
│                          User Side (censorship-resistant)                     │
│                                     │                                        │
│   ┌─────────────────────────────────┴────────────────────────────────────┐   │
│   │                         pokerface CLI                                │   │
│   │  1. Read Git metadata: tag → Commit SHA → Image Digest               │   │
│   │  2. Request Manifest from Registry (get CDN URLs / presigned URLs)   │   │
│   │  3. Download blobs from CDN via skopeo / built-in HTTP client        │   │
│   │  4. Verify digests, import into local container runtime              │   │
│   └─────────────────────────────────┬────────────────────────────────────┘   │
│                                     │                                        │
│                                     ▼                                        │
│   ┌──────────────────────────────────────────────────────────────────────┐  │
│   │        Local Container Runtime (Docker / containerd / podman)         │  │
│   │        Image imported; docker run / podman run works as usual         │  │
│   └──────────────────────────────────────────────────────────────────────┘  │
│                                                                              │
│   Note: no docker pull to registry-1.docker.io—TLS timeouts avoided.         │
└──────────────────────────────────────────────────────────────────────────────┘
```

## Pull Sequence

```text
User            pokerface CLI        Git Remote         Registry/Metadata       CDN/Object Storage   Local Runtime
 │                   │                    │                    │                    │                    │
 │ pokerface pull    │                    │                    │                    │                    │
 │ repo:tag          │                    │                    │                    │                    │
 ├──────────────────▶│                    │                    │                    │                    │
 │                   │                    │                    │                    │                    │
 │                   │ 1. resolve tag→commit                   │                    │                    │
 │                   ├───────────────────▶│                    │                    │                    │
 │                   │◀───────────────────┤                    │                    │                    │
 │                   │   Commit SHA       │                    │                    │                    │
 │                   │                    │                    │                    │                    │
 │                   │ 2. read metadata, get image digest      │                    │                    │
 │                   ├───────────────────▶│                    │                    │                    │
 │                   │◀───────────────────┤                    │                    │                    │
 │                   │   Digest           │                    │                    │                    │
 │                   │                    │                    │                    │                    │
 │                   │ 3. request Manifest│                    │                    │                    │
 │                   ├────────────────────┼───────────────────▶│                    │                    │
 │                   │                    │                    │ return Manifest    │                    │
 │                   │                    │                    │ (Blob→CDN URL/     │                    │
 │                   │◀───────────────────┼────────────────────┤  presigned URL)    │                    │
 │                   │                    │                    │                    │                    │
 │                   │ 4. download blobs (HTTPS, via CDN domain)                   │                    │
 │                   ├────────────────────┼────────────────────┼───────────────────▶│                    │
 │                   │◀───────────────────┼────────────────────┼────────────────────┤                    │
 │                   │   blob stream      │                    │                    │                    │
 │                   │                    │                    │                    │                    │
 │                   │ 5. verify digests  │                    │                    │                    │
 │                   │ 6. import to local runtime              │                    │                    │
 │                   ├────────────────────┼────────────────────┼────────────────────┼───────────────────▶│
 │                   │                    │                    │                    │                    │
 │◀──────────────────┤ done               │                    │                    │                    │
 │                   │                    │                    │                    │                    │
```

Failure fallback: Git resolution failure → hard error; manifest request failure → fall back to the verified local manifest cache; blob failure → per-blob retry with digest verification; import failure → temp files cleaned up. The implemented behavior is in [docs/spec/pull.md](docs/spec/pull.md).

## Quick Start

Install (or build from source — `docs/install.md` has both):

```bash
curl -fsSL https://raw.githubusercontent.com/daqing/pokerface/main/install.sh | sh
pokerface version
```

The whole loop works locally with no Docker Hub — a registry on your
machine, an image built `FROM scratch`:

```bash
# Start a local registry (docs/registry/operations.md has the real one)
registry --config registry.yaml &

# In your application repository (docs/getting-started.md walks this):
pokerface build --write-lock     # buildx builds, pokerface pushes, lock records the digest
git add pokerface.lock.yaml && git commit -m "pokerface: update lock"

# Consume it anywhere:
pokerface resolve github.com/you/app:main    # tag → commit → digest
pokerface pull github.com/you/app:main       # verify + import into Docker/podman
docker run --rm 127.0.0.1:4599/hello/app:latest
```

The full walkthrough with expected output is
[docs/getting-started.md](docs/getting-started.md) (中文:
[docs/getting-started.zh-CN.md](docs/getting-started.zh-CN.md)); the
complete command surface is [docs/reference/cli.md](docs/reference/cli.md).

### Verify the whole path in one command

```bash
./scripts/e2e.sh          # the M4 demo: build → push → lock → resolve → pull → HTTP 200
./scripts/e2e-m2.sh       # the M2 registry: skopeo push, protocol edges, auth
./scripts/e2e-m1.sh       # the M1 client: resolve/pull/offline/cache
```

Each script builds the binaries, runs against a local registry, and asserts
its steps; failures keep per-step logs. `pokerface cache verify` checks and
repairs the cache; `pokerface cache rm` clears it. The flows are specified
in `docs/spec/pull.md`, `docs/spec/build-plan.md`, `docs/spec/push.md`, and
`docs/spec/cache.md`.

## Design Notes

- **Git stores metadata only**: Dockerfile and `pokerface.yaml` (build args, tag rules, target registry) live alongside application code. Image layer binaries never enter Git.
- **Content-addressed blobs, long CDN caching**: Image layers are immutable by digest, ideal for long-term CDN caching. Manifests change with tags, so they use short caching or origin fallback.
- **Auth separated from storage**: The Registry issues short-lived presigned URLs or tokens, preventing public exposure of blobs.
- **OCI Distribution Spec compatible**: Exposes `/v2/` endpoints; blobs in Manifests point to CDN, so standard clients can theoretically consume it too.
- **Censorship-resistant pulling**: `pokerface pull` stays on domains/CDNs you control and never triggers requests to `registry-1.docker.io`. Under the hood it may use `skopeo` or a built-in HTTP client to download and import.

## Roadmap

- [x] CLI skeleton and `pokerface.yaml` spec definition (T1.1, T1.4)
- [x] Git metadata resolution (tag → Commit → Digest) (T1.6–T1.9)
- [x] Minimal Registry/metadata service (Manifest + presigned URLs) (M2: T2.1–T2.19)
- [x] CDN/object storage backend integration (S3/MinIO compatible) (T2.4–T2.6)
- [x] `skopeo` integration and local runtime import (T1.13)
- [x] Build trigger and CI templates (M4: T4.1–T4.7, ADR 0001)
- [x] Docs site and end-to-end example (T4.8–T4.15)
- [ ] Post-v0.1: floating semver tags, Basic credentials → token exchange,
      a registry garbage collector, and the runtime socket-write fix
      (`docs/notes/runtime-capabilities.md`)

## Contributing

Issues and PRs are welcome. Please read `CONTRIBUTING.md` before submitting, and ensure new features come with tests and documentation updates.

## License

MIT

## Translation

[简体中文](README.zh-CN.md)
