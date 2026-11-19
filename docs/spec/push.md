# The Push Pipeline (T4.3)

> Status: v0.1, implemented by `src/push.emo` (task T4.3). The push takes
> the validated OCI layout a build produced (`docs/spec/build-plan.md`) to
> the registry over the M1 client's transport
> (`docs/spec/registry-client.md`): blobs first, manifests last, digests
> verified everywhere. Spec references: `docs/spec/registry-uploads.md` for
> the upload protocol.

## Endpoint and repository

The image reference in `pokerface.yaml` is the push target: its host (and
port) is the registry endpoint — loopback hosts go over `http://`,
everything else over `https://` (the same rule as pull). `push-smoke/app`
is the repository on the wire; every rendered tag is applied there.

The registry token comes from the client settings
(`POKERFACE_REGISTRY_TOKEN` or `config.yaml`'s `registry.token`); a request
that is challenged runs the Bearer dance with the scope
`repository:<repo>:pull,push` — pull for the existence checks, push for the
uploads — and the failed request replays once with the new token.

## The stages

1. **Blob existence** — `HEAD /v2/<repo>/blobs/<digest>`; a 200 skips the
   blob without reading (or sending) a byte, so a repeat push uploads
   nothing that is already there. HEAD rides its own transport (headers
   only): the std http client reads a HEAD response's declared
   Content-Length as a body — a body HEAD responses never carry — so the
   probe speaks HTTP/1.1 over `net` and stops after the headers.
2. **Blob upload** — small blobs in one request
   (`POST /v2/<repo>/blobs/uploads/?digest=<d>` with the whole body, 201);
   blobs over the 4 MiB single-request limit go out as a session
   (`POST` → 202 + Location, `PATCH` chunks of 4 MiB with the spec's bare
   `Content-Range` offsets, closing `PUT ?digest=<d>` → 201).
3. **Manifests by digest** — real registries validate an index's children
   against their manifest tables, so every descriptor in the layout's
   `index.json` is PUT as `/v2/<repo>/manifests/<digest>` with its media
   type before anything references it; nested indexes (buildx's
   multi-platform wrapper) recurse children-first. buildx writes one
   descriptor per `--tag`, all naming the same manifest — they are deduped
   by digest.
4. **Tag application** — a layout whose (deduped) index carries exactly one
   manifest child tags **the manifest** (the maximally compatible answer
   for single-platform builds); otherwise it tags **the index**. The same
   bytes go out under every rendered tag.

## Verification and retries

Every manifest PUT's `Docker-Content-Digest` answer must equal the pushed
bytes' local sha256 — a mismatch is an integrity failure (exit 7), never a
silent re-tag. Transport errors and 5xx retry (3 attempts, 0.5 s apart);
the pipeline is idempotent — digest-addressed uploads, HEAD skips,
INSERT-OR-REPLACE manifests — so a mid-flight failure replays without
corrupting existing tags. 401 on an upload surfaces the registry's own
error envelope (exit 5).

## Progress and output

Progress streams to stdout as it happens (`--json` keeps stdout to the one
report object and silences it):

```text
skip blob sha256:d56f… (already on the registry)
push blob sha256:2ab8… (476 bytes)
push manifest sha256:6241…
push tag latest -> sha256:6241…
```

The command's summary line reports the counts:
`pushed: 127.0.0.1:4592/push-smoke/app (2 uploaded, 1 skipped)`.
`--json` carries `pushed` and the tag `digest` in the build report. The
digest the tags now point at is what T4.4's lock write-back records.

## Registry-side notes

- The `/api/v1/resolve` platform walk recurses into nested indexes (the
  buildx shape) and takes a platformless manifest child's platform from its
  config blob — a nested wrapper never answers as an empty platform.
- Pushing to an auth-enabled registry needs a token with the push scope;
  the token exchange (`/token`, Basic) is done out of band (CI mints the
  token, or skopeo) — the client itself sends Bearer tokens only.
