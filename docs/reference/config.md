# Configuration Reference

> The client's configuration surface (T4.10), implemented by
> `src/settings.emo` (T1.8). The registry service's own configuration is a
> different document: `docs/spec/registry-config.md`. Precedence and
> parsing: `docs/spec/config.md`.

## Precedence

1. CLI flags (`--config <path>` names the client config file);
2. environment variables (below);
3. the client config file;
4. built-in defaults.

The client config file is located in this order: `--config` >
`POKERFACE_CONFIG` > `$XDG_CONFIG_HOME/pokerface/config.yaml` >
`~/.config/pokerface/config.yaml`. A file that does not parse is an error,
never silently ignored; unknown fields are rejected with the field's path.

**For `pokerface build`, `--config` names the build file (`pokerface.yaml`)
instead** — the build file and the client config are different documents
(`docs/spec/pokerface-yaml.md` vs this one), and the build command never
reads the client config file for its plan.

## The client config file

```yaml
registry:
  url: https://registry.example.com
  token: "…"
cache_dir: /path/to/cache
```

| Field | Required | Default | Effect |
| --- | --- | --- | --- |
| `registry.url` | no | *(unset)* | The registry base URL for pulls; must start `https://` (or `http://` for a local development registry). |
| `registry.token` | no | *(unset)* | A Bearer token for registry authentication. Never printed — logs and summaries carry `<redacted:N>` only. |
| `cache_dir` | no | the XDG cache default (`~/.cache/pokerface`) | The local cache root. |

## Environment variables

| Variable | Effect | Applies to |
| --- | --- | --- |
| `POKERFACE_CONFIG` | The client config file path (first candidate after `--config`) | every command that loads settings |
| `POKERFACE_REGISTRY_URL` | Overrides `registry.url` | resolve, pull |
| `POKERFACE_REGISTRY_TOKEN` | Overrides `registry.token` | resolve, pull, **build's push stage** |
| `POKERFACE_CACHE_DIR` | Overrides `cache_dir` | pull, cache |
| `POKERFACE_CACHE_TTL` | Cache TTL: `<n>`, `<n>s/m/h/d` (e.g. `7d`); 0 disables | pull, cache |
| `POKERFACE_CACHE_MAX_SIZE` | Cache size cap: `<n>`, `<n>K/M/G/T` (1024-based, e.g. `2G`); 0 disables | pull, cache |

Malformed values (`POKERFACE_CACHE_TTL=seven`) are hard errors, not
warnings. Secrets live only in the environment or the config file; the
`--verbose` settings summary prints `<redacted:N>` for the token and
nothing else sensitive.

## What is not configurable in v0.1

- The build tool: buildx-capable docker first, podman second — detection
  runs against `PATH` (`docs/spec/build-plan.md`); `POKERFACE_BUILD_*`
  overrides do not exist yet.
- The registry service's port, store, auth, and limits: the server has its
  own config and its own `POKERFACE_REGISTRY_*` variables — the two families
  do not overlap (`docs/spec/registry-config.md`).
- Timeouts: fixed per operation (git 10–30 s, manifest 60 s, blob 300 s,
  build watchdog 1800 s).
