# The pokerface registry image (T2.17).
#
# Stage 1 builds the registry with the Emo toolchain. The c target compiles
# generated C with a C compiler, so the builder needs gcc plus the toolchain
# itself. The default builder image bundles the emo compiler; set
# EMO_BUILDER_IMAGE to an image carrying your own build (the toolchain is
# young — see docs/registry/deployment.md).
#
# Stage 2 runs the binary. The c target links libsqlite3 (the registry's
# metadata store) and, with a toolchain whose reachability walk sees the
# httpd TLS tier, OpenSSL; the slim runtime installs both. Everything else —
# the HTTP server, the filesystem blob store, YAML/JSON, SHA-256 — is
# compiled into the binary.

ARG EMO_BUILDER_IMAGE=ghcr.io/emo-lang/emo-builder:0.1.0

FROM ${EMO_BUILDER_IMAGE} AS builder

WORKDIR /src
COPY package.emo package.lock ./
COPY src ./src
COPY registry ./registry
# The toolchain resolves the pinned packages from its registry cache; the
# build itself needs no network when the cache is warm.
RUN emo build -o /out/pokerface-registry registry/main.emo


FROM debian:bookworm-slim AS runtime

RUN apt-get update \
 && apt-get install -y --no-install-recommends libsqlite3-0 libssl3 wget ca-certificates \
 && rm -rf /var/lib/apt/lists/*

RUN useradd --system --home /data --shell /usr/sbin/nologin pokerface \
 && mkdir -p /data && chown pokerface:pokerface /data

COPY --from=builder /out/pokerface-registry /usr/local/bin/pokerface-registry
COPY deploy/registry-entrypoint.sh /usr/local/bin/registry-entrypoint
RUN chmod +x /usr/local/bin/registry-entrypoint

USER pokerface
WORKDIR /data
EXPOSE 5000

# The service owns its shutdown protocol: the entrypoint turns SIGTERM into
# the marker file the main loop watches (the server ignores signals by
# design), then waits for the drain.
ENTRYPOINT ["/usr/local/bin/registry-entrypoint"]

HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:5000/healthz || exit 1
