# The hello example (T4.13)

A minimal, dependency-free application that exercises the whole pokerface
path: Git metadata → build → push → lock → pull → **a container that
actually serves HTTP 200**. **Docker Hub is not required** — the image is
`FROM scratch` (one static binary, nothing else) and the registry runs on
your machine.

## Contents

| File | What it is |
| --- | --- |
| `main.go` | The service: `/` answers 200 with a message, `/healthz` answers `ok`. Pure stdlib. |
| `hello-linux-amd64`, `hello-linux-arm64` | Prebuilt static binaries (CGO off, `-trimpath -ldflags "-s -w"`) for the two example platforms. |
| `Dockerfile` | `FROM scratch`, `COPY hello-linux-${TARGETARCH} /hello` — buildx substitutes the architecture per platform. |
| `pokerface.yaml` | The build input: two platforms, `latest` + `sha-{{ commit.short }}` tags, a local registry. |

The binaries are checked in so the example builds without a Go toolchain;
to rebuild them:

```console
$ GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o hello-linux-amd64 main.go
$ GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o hello-linux-arm64 main.go
```

## Run it

1. **A local registry** (from the quick start):

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
   ```

2. **Point the example at a registry you can push to.** The committed
   `pokerface.yaml` uses `127.0.0.1:4599/hello/app` — edit the `image` and
   `registry.url` lines if yours differs.

3. **Build, push, and write the lock** (the commit the Git facts come from
   is whatever repository this directory lives in — for the pokerface
   checkout itself, that is `github.com/daqing/pokerface` at its current
   HEAD; the OCI `revision` label and the lock agree on it):

   ```console
   $ cd examples/hello
   $ pokerface build --write-lock
   tool:       docker
   digest:     sha256:… (application/vnd.oci.image.index.v1+json)
   tags:       latest, sha-<short>
   pushed:     127.0.0.1:4599/hello/app (6 uploaded, 0 skipped)
   lock:       …/examples/hello/pokerface.lock.yaml
   ```

   The two-platform build answers an image index; the streamed lines above
   are buildx's own log.

4. **Resolve, pull, run, and check the 200:**

   ```console
   $ pokerface pull examples/hello:main
   $ docker run -d --rm --name hello -p 8080:8080 127.0.0.1:4599/hello/app:latest
   $ curl -si http://127.0.0.1:8080/ | head -1
   HTTP/1.1 200 OK
   $ curl -s http://127.0.0.1:8080/
   hello from a pokerface-built image
   $ docker stop hello
   ```

**Expected image size**: ~5.5 MiB per platform (one static Go binary), the
multi-platform index on the registry serves both.

## What the image does NOT contain

No build cache, no layer with tooling, no secrets, no credentials — the
image is exactly one static binary plus the `PORT` env default. The only
metadata is the OCI labels the build writes (`revision`, `source`,
`version`, `created`); `docker image inspect` shows them, and the lock
records the digest they were built from.

## Feeding the CI template

Copy `.github/workflows/publish.yaml` (T4.6) into a repository containing
this directory, set `POKERFACE_REGISTRY_TOKEN`, and every branch push /
`v*` tag / manual dispatch builds and pushes it and commits the lock back
with `[skip ci]` — the example is exactly the template's target shape
(`pokerface.yaml` at the path the workflow runs in).
