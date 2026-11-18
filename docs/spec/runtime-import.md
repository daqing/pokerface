# Runtime Import (T1.13)

> Status: v0.1, implemented by `src/runtime.emo`. Takes the OCI image layout
> assembled by T1.12 and imports it into a local container runtime through
> skopeo's local transports. Tool detection, planning, and execution are
> separate steps, and the command runner is injectable, so every command and
> error path is testable without a runtime.

## Selection

`pokerface pull` (T1.14) plans an import with `prepare(runner, requested,
request)`, which detects the installed tools and then plans:

| Requested | Selected when |
| --- | --- |
| `""` (auto) | Docker, else Podman, else containerd. |
| `docker` | Docker must be installed. |
| `podman` | Podman must be installed. |
| `containerd` / `ctr` | `ctr` must be installed. |

Detection probes each binary with `--version`; any failure (including exit
127 from the execvp path) counts as unavailable. An explicit runtime that is
not installed is an error — there is no silent fallback to a different
runtime. When nothing is installed:

```text
runtime: no container runtime found (checked docker, podman, ctr); install Docker, Podman, or containerd and retry
```

**skopeo is required for every path.** Without it, planning fails early with
an installation hint instead of a half-run import:

```text
runtime: importing into docker requires skopeo. Install it and retry (macOS: brew install skopeo; Debian/Ubuntu: apt-get install skopeo; Fedora: dnf install skopeo).
```

## Support matrix

| Runtime | Import transport | Import commands | Verification | Failure cleanup |
| --- | --- | --- | --- | --- |
| Docker | `docker-daemon:` | `skopeo copy oci:<dir>:<tag> docker-daemon:<image>:<tag>` | `docker image inspect <image>:<tag>` | `docker image rm <image>:<tag>` when the tag did not exist before |
| Podman | `containers-storage:` | `skopeo copy oci:<dir>:<tag> containers-storage:<image>:<tag>` | `podman image inspect <image>:<tag>` | `podman image rm <image>:<tag>` when the tag did not exist before |
| containerd | `oci-archive:` + `ctr` | `skopeo copy oci:<dir>:<tag> oci-archive:<dir>.oci-archive.tar:<tag>` then `ctr images import --base-name <image> <dir>.oci-archive.tar` | `ctr images ls --quiet`, exact-line match on `<image>:<tag>` | `ctr images rm <image>:<tag>` when absent before; archive always removed (unless kept) |

The archive for containerd is written next to the layout as
`<layout_dir>.oci-archive.tar`.

## Verification and cleanup

The importer records whether `<image>:<tag>` already exists, runs the import
commands, and then verifies the tag exists. Outcomes:

- **Success** — a result carrying the runtime, the full ref, and the archive
  path (empty for Docker/Podman); a containerd archive is removed unless the
  request said to keep it.
- **Any failure** (import command error, or success reported but the tag is
  missing) — the temp archive is removed, and the target tag is removed
  **only if it did not exist before the import**. A pre-existing image is
  never touched, and a failed run leaves no partial image under the target
  tag and no temp archive.

## Error mapping

Runner failures are formatted by the shared `RealRunner` as
`git: '<tool>' exited with code N: <output>`; the `git:` prefix is stripped
before mapping.

| Observed failure | Message |
| --- | --- |
| exit 127 | `runtime: '<tool>' is not installed or not on PATH (…)` |
| `Cannot connect to the Docker daemon`, `Is the docker daemon running`, `Cannot connect to Podman`, `connection refused`, missing `docker.sock` | `runtime: cannot reach the container runtime while trying to import into <runtime>; start Docker, Podman, or containerd and retry (…)` |
| `permission denied` | `runtime: permission denied while trying to import into <runtime>; check access to the runtime socket (…)` |
| anything else | `runtime: import into <runtime> failed: <reason>` |

## Limitations

- Podman is imported with `containers-storage:` (the transport the task
  specifies). Rootless podman and a rootful daemon use different storage;
  the import lands in whichever storage the current user's skopeo/podman
  share.
- The containerd path assumes a `ctr` whose `images import` supports
  `--base-name` (present in containerd 1.2 and later). `--base-name <image>`
  combines with the archive's `ref.name` tag to produce
  `<image>:<tag>` on import.
- No automatic fallback happens between runtimes after a failed import; T1.14
  surfaces the error and leaves retry decisions to the user.
