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

Failure fallback (to be made explicit in implementation): Git resolution failure → hard error; Manifest request failure → fall back to local cache; CDN download failure → per-blob retry with digest verification; runtime import failure → clean up temp files.

## Quick Start

> Commands below reflect the planned CLI shape and will be updated as implementation progresses.

```bash
# Install
curl -fsSL https://pokerface.mindwork.cool/install.sh | sh

# Pull an image (resolve from Git metadata, download via CDN, import into local Docker)
pokerface pull github.com/you/app:latest

# Inspect resolution (tag → Commit → Digest)
pokerface resolve github.com/you/app:latest

# Build and push (called from CI)
pokerface build --repo github.com/you/app --push
```

## Design Notes

- **Git stores metadata only**: Dockerfile and `pokerface.yaml` (build args, tag rules, target registry) live alongside application code. Image layer binaries never enter Git.
- **Content-addressed blobs, long CDN caching**: Image layers are immutable by digest, ideal for long-term CDN caching. Manifests change with tags, so they use short caching or origin fallback.
- **Auth separated from storage**: The Registry issues short-lived presigned URLs or tokens, preventing public exposure of blobs.
- **OCI Distribution Spec compatible**: Exposes `/v2/` endpoints; blobs in Manifests point to CDN, so standard clients can theoretically consume it too.
- **Censorship-resistant pulling**: `pokerface pull` stays on domains/CDNs you control and never triggers requests to `registry-1.docker.io`. Under the hood it may use `skopeo` or a built-in HTTP client to download and import.

## Roadmap

- [ ] CLI skeleton and `pokerface.yaml` spec definition
- [ ] Git metadata resolution (tag → Commit → Digest)
- [ ] Minimal Registry/metadata service (Manifest + presigned URLs)
- [ ] CDN/object storage backend integration (S3/MinIO compatible)
- [ ] `skopeo` integration and local runtime import
- [ ] Build trigger and CI templates
- [ ] Docs site and end-to-end example

## Contributing

Issues and PRs are welcome. Please read `CONTRIBUTING.md` before submitting, and ensure new features come with tests and documentation updates.

## License

MIT

## Translation

[简体中文](README.zh-CN.md)
