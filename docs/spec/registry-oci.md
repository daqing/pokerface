# Registry OCI Documents (T2.3)

> Status: v0.1, implemented by `registry/oci.emo`. Tests:
> `test/registry_oci.emo` under `emo test`.

The registry's model of what clients push: OCI image manifests, OCI image
indexes, and image configs. Every document is untrusted input, so parsing is
the validation boundary.

## Types

| Type | Members |
| --- | --- |
| `Descriptor` | `media_type`, `digest`, `size`, `annotations` |
| `Platform` | `os`, `architecture`, `variant`, `os_version` |
| `IndexEntry` | `descriptor`, `platform` |
| `ImageManifest` | `media_type`, `config`, `layers`, `annotations` |
| `ImageIndex` | `media_type`, `manifests`, `annotations` |
| `Document` | `kind` (`manifest`/`index`), `media_type`, `manifest`, `index` |
| `ImageConfig` | `architecture`, `os`, `variant`, `os_version`, `diff_ids`, `labels` |

`Document` holds both shapes because Emo has no sum types: `kind` says which
one is live, the other is the absent placeholder (`absent_manifest()`,
`absent_index()`).

## Accepted media types

| Kind | Types |
| --- | --- |
| manifest | `application/vnd.oci.image.manifest.v1+json`, `application/vnd.docker.distribution.manifest.v2+json` |
| index | `application/vnd.oci.image.index.v1+json`, `application/vnd.docker.distribution.manifest.list.v2+json` |

The config and layer media types are accepted as any well-formed
`type/subtype` string — OCI permits artifact types and foreign layers the
registry should not judge. The document's own type must be one of the four
above.

## Parsing

| Entry point | Notes |
| --- | --- |
| `parse_document(body, content_type)` | Resolves the type from the `Content-Type` header (parameters stripped, matched case-sensitively) and the body's `mediaType`; the two must agree. Either alone is enough. |
| `parse_manifest(body, media_type)` | Caller-supplied type wins when the body omits `mediaType`; a contradiction is an error. |
| `parse_index(body, media_type)` | Same rule. |
| `parse_config(body)` | `architecture`, `os`, `rootfs.type` = `layers`, and `rootfs.diff_ids` are required; `config.Labels` is read; other members are not modeled. |

Rejected, each with the offending path in the message
(`registry: oci: manifest: config: digest: …`):

- a body that is not JSON, or not a JSON object;
- `schemaVersion` missing, not an integer, or not `2`;
- a missing `config`, `layers`, or `manifests`, or the wrong JSON kind;
- a descriptor missing `mediaType`, `digest`, or `size`;
- a digest that is not `sha256:` plus exactly 64 lowercase hex characters;
- a media type that is empty, has no `/`, or contains whitespace;
- a negative or non-integer size;
- an annotation that is not a string, or an empty annotation key;
- a `Content-Type`/`mediaType` disagreement, or neither of them naming a
  supported type.

Parsing answers `(R.error, reason)` for every one of these — it never raises.
The JSON accessors raise on a missing key and Emo has no catch, so every
member goes through a scanning `member()` first.

## Digest and size verification

`verify_body(descriptor, body, label)` hashes the body, compares it with the
descriptor's digest, and compares the byte length with its size. It answers
the verified digest so a caller can store it without recomputing. A mismatch
names both values:

```text
registry: oci: manifest: sha256:…: digest mismatch — body hashes to sha256:…
registry: oci: manifest: sha256:…: size mismatch — descriptor says 401, body is 402 bytes
```

## Platform selection

`select_platform(index, os, arch)` returns the first entry whose `os` and
`architecture` match exactly. Variants are ignored, matching the client
(`src/registry.emo`'s `select_platform`), so `linux/arm64` selects the
`variant: v8` entry. A miss lists what the index does offer:

```text
registry: oci: index lists no windows/amd64 manifest (available: linux/amd64 linux/arm64 sha256:… (no platform))
```

## Encoding

`encode_manifest`, `encode_index`, `encode_config`, and `encode_document` emit
compact JSON with a fixed field order and omit empty optional members. The
same value always encodes to the same bytes, so a digest taken over the
encoding is stable.

Encoding is canonical, **not lossless**: it emits the modeled fields and drops
unknown members (`subject`, `artifactType`, `urls`, `history`, …). The
registry stores and serves the original bytes a client pushed — the
`Docker-Content-Digest` always covers what was received — so this encoder is
for constructing documents, not for round-tripping arbitrary input.

## Fixtures and tests

`test/fixtures/oci/` holds a skopeo-inspectable single-layer image
(`manifest.json`, `config.json`, `layer-0.tar.gz`), a multi-arch
`index.json` over it, a Docker schema2 `manifest.docker.json`, and the golden
canonical encodings `manifest.canonical.json` / `index.canonical.json`.
`test/registry_oci.emo` covers real fixture parsing, every rejection above,
Content-Type resolution, byte-exact encoding, platform selection parity with
the client, and `verify_body`.
