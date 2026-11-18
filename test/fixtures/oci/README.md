# OCI layout fixtures (T1.12, extended by T2.3)

A minimal but valid single-layer image used by `test/oci_layout.emo` and, when
skopeo is installed, by the live `skopeo inspect oci:<dir>:latest` check.
T2.3's registry parser tests use the same image plus an index over it.

| File | Role |
| --- | --- |
| `manifest.json` | OCI image manifest; config and layer digests/sizes are computed from the two files below. |
| `config.json` | OCI image config; `rootfs.diff_ids` holds the digest of the **uncompressed** layer tar. |
| `layer-0.tar.gz` | A gzipped ustar archive containing one file, `hello.txt`. |
| `manifest.canonical.json` | The compact, fixed-order encoding the registry model must reproduce byte for byte; its own digest (`sha256:3c5537…`, 402 bytes) is the amd64 index entry. |
| `index.json` | Multi-arch OCI index over `manifest.canonical.json` (amd64), a synthetic arm64/v8 entry, and an attestation entry with no platform. |
| `index.canonical.json` | The canonical encoding of `index.json`. |
| `manifest.docker.json` | A Docker schema2 manifest, for the Docker media types. |

`manifest.json` is byte-stable on purpose (its own bytes are the manifest
digest). If you change `config.json` or `layer-0.tar.gz`, update the matching
`digest` and `size` in `manifest.json`; otherwise `assemble` rejects the
fixture with a digest or size mismatch — which is exactly what the tests are
supposed to catch.

The canonical files are compact JSON with a trailing newline; the tests compare
`encode(...) + "\n"` against them. Regenerate them with `registry/oci.emo`'s
encoder after changing a model field — the golden test will fail until they
match.

`manifest.json` is byte-stable on purpose (its own bytes are the manifest
digest). If you change `config.json` or `layer-0.tar.gz`, update the matching
`digest` and `size` in `manifest.json`; otherwise `assemble` rejects the
fixture with a digest or size mismatch — which is exactly what the tests are
supposed to catch.

Regenerating the layer:

```console
$ printf 'hello from a pokerface fixture\n' > hello.txt
$ tar --format=ustar -cf layer-0.tar hello.txt
$ gzip -n -9 -c layer-0.tar > layer-0.tar.gz
$ shasum -a 256 layer-0.tar            # -> config.json rootfs.diff_ids
$ shasum -a 256 layer-0.tar.gz         # -> manifest.json layers[0].digest
$ wc -c layer-0.tar.gz                 # -> manifest.json layers[0].size
```

`gzip -n` keeps the timestamp out of the compressed bytes, so regeneration
after an edit produces the same archive on any machine.
