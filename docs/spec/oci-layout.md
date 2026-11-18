# OCI Image Layout (T1.12)

> Status: v0.1, implemented by `src/oci.emo`. The pull path downloads an
> image manifest with `src/registry.emo` (T1.10) and its config/layers with
> `src/blob.emo` (T1.11); this module assembles those bytes into a standard
> [OCI Image Layout](https://github.com/opencontainers/image-spec/blob/main/image-layout.md)
> that `skopeo`, `podman`, and `ctr` can read.

## On disk

```text
<dir>/
  oci-layout              {"imageLayoutVersion": "1.0.0"}
  index.json              OCI image index with one manifest descriptor
  blobs/sha256/<hex>      manifest, config, and layer blobs
```

`index.json` references the image manifest and names it with the
`org.opencontainers.image.ref.name` annotation:

```json
{
  "schemaVersion": 2,
  "mediaType": "application/vnd.oci.image.index.v1+json",
  "manifests": [
    {
      "mediaType": "application/vnd.oci.image.manifest.v1+json",
      "digest": "sha256:…",
      "size": 477,
      "annotations": {
        "org.opencontainers.image.ref.name": "latest"
      }
    }
  ]
}
```

The descriptor's `mediaType` is the media type the registry served
(OCI manifest or Docker v2 manifest); `type` is omitted, as the OCI spec
requires.

## Assembly

`assemble(dir, LayoutSpec)` takes the already-downloaded manifest bytes, the
manifest digest the registry/lock advertised, one `BlobSource` per config and
layer (`digest`, `size`, local `path`), and the tag. It:

1. hashes the manifest bytes and rejects a disagreement with the advertised
   digest;
2. parses the manifest and pairs each config/layer descriptor with a source,
   rejecting a missing source, a declared-size disagreement, or an
   unreferenced extra source **before writing anything**;
3. creates `blobs/sha256/` and copies each source there, hashing and counting
   while copying and renaming `<dest>.part` into place only after digest and
   size verification;
4. writes the manifest bytes as a blob;
5. writes `oci-layout` and, as the commit point, `index.json` last.

An existing identical blob is reused, so re-running assembly onto the same
directory is idempotent. A partial or corrupted copy never receives its final
name, and `index.json` is never written when a blob failed.

The manifest must be an image manifest: `schemaVersion` 2, a required
`config` descriptor, and a `layers` array (possibly empty). An index/list is
selected per platform by T1.10 before assembly.

## Validation

`validate(dir)` checks the layout from the outside in:

- `oci-layout` exists, parses, and declares `imageLayoutVersion` `1.0.0`;
- `index.json` exists, parses, and has a `manifests` array;
- every descriptor's blob exists, hashes to the named `sha256:` digest, and
  matches the descriptor's size;
- every manifest's config and layer descriptors pass the same checks;
- nested indexes/lists are followed recursively.

It answers `(manifests, unique blobs, unique bytes)`. A non-image media type
is an error rather than being silently skipped.

## Errors

All failures are single-line reasons:

```text
oci: manifest: config: missing required field
oci: missing blob sha256:… (manifest: layers[0]): no downloaded file was provided
oci: manifest: layers[0]: digest mismatch — descriptor says sha256:a…, copied bytes hash to sha256:b…
oci: manifest: layers[0]: size mismatch — descriptor says 142 bytes, the source has 141
oci: blob sha256:… (manifest: config): digest mismatch — the file hashes to sha256:…
oci: missing blob sha256:… (index.json: manifests[0].layers[0]): blobs/sha256/… cannot be read: …
oci: <dir> is not an OCI image layout: oci-layout is missing (…)
```

## Temporary layouts

`new_temp_layout(keep)` creates a unique directory under `$TMPDIR` (or
`/tmp`) named `pokerface-oci-<pid>-<n>`. `TempLayout.cleanup()` removes the
whole tree unless `keep` is true; it refuses to recurse into a path that does
not carry the generated `pokerface-oci-` shape. The pull command's
`--keep-temp` / `--keep` flag maps onto the keep parameter. The flag exists so
a failed import can be diagnosed from the exact layout that was handed to the
runtime (T1.13/T1.14).
