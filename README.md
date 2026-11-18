# PokerFace

An open-source Docker alternative that distributes container images via Git remote repositories.

Git manages metadata and build context, CDN/object storage manages binary layers, and `pokerface` glues them together. It provides **censorship-resistant image pulling**—no `docker pull` request ever hits `registry-1.docker.io`, eliminating TLS timeouts by design.



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

> The M1 client (`resolve`, `pull`, `cache`, `version`) is implemented; `build` lands in a later milestone.

```bash
# Pull an image (resolve from Git metadata, download via CDN, import into local Docker)
pokerface pull github.com/you/app:latest

# Inspect resolution (tag → Commit → Digest)
pokerface resolve github.com/you/app:latest

# Build and push (planned for a later milestone)
pokerface build --repo github.com/you/app --push
```

### M1 client walkthrough

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

`pokerface pull <ref> --offline` repeats the pull from the local cache after
one online run. `pokerface cache verify` checks the cache and evicts damaged
entries; `pokerface cache rm` clears it. The M1 flow is specified in
`docs/spec/pull.md` and `docs/spec/cache.md`.

For a fully local check — a fixture Git repository plus an Emo mock
registry/CDN, no Docker Hub — run:

```bash
./scripts/e2e-m1.sh
```

It builds the CLI, resolves and pulls the fixture image, verifies the offline
second pull and the cache commands, and imports into the detected runtime when
skopeo plus docker/podman/ctr are available. Set `KEEP_TMP=1` to keep the
temp directory and logs.

## Design Notes

- **Git stores metadata only**: Dockerfile and `pokerface.yaml` (build args, tag rules, target registry) live alongside application code. Image layer binaries never enter Git.
- **Content-addressed blobs, long CDN caching**: Image layers are immutable by digest, ideal for long-term CDN caching. Manifests change with tags, so they use short caching or origin fallback.
- **Auth separated from storage**: The Registry issues short-lived presigned URLs or tokens, preventing public exposure of blobs.
- **OCI Distribution Spec compatible**: Exposes `/v2/` endpoints; blobs in Manifests point to CDN, so standard clients can theoretically consume it too.
- **Censorship-resistant pulling**: `pokerface pull` stays on domains/CDNs you control and never triggers requests to `registry-1.docker.io`. Under the hood it may use `skopeo` or a built-in HTTP client to download and import.

## Roadmap

- [x] CLI skeleton and `pokerface.yaml` spec definition
- [x] Git metadata resolution (tag → Commit → Digest)
- [ ] Minimal Registry/metadata service (Manifest + presigned URLs)
- [ ] CDN/object storage backend integration (S3/MinIO compatible)
- [x] `skopeo` integration and local runtime import
- [ ] Build trigger and CI templates
- [ ] Docs site and end-to-end example

## Contributing

Issues and PRs are welcome. Please read `CONTRIBUTING.md` before submitting, and ensure new features come with tests and documentation updates.

## License

MIT

## Translation

[简体中文](README.zh-CN.md)
