# Configuration Specification (T1.8)

> Status: v0.1, implemented by `src/settings.emo`. The config file carries
> the values the CLI needs before touching a repository: the registry
> address, its bearer token, and where the local cache lives.

## File location and precedence

The config file is the first of these that exists:

1. `--config <path>` — must exist; a missing file is an error, not a skip.
2. `POKERFACE_CONFIG` — must exist; a missing file is an error.
3. `$XDG_CONFIG_HOME/pokerface/config.yaml`
4. `$HOME/.config/pokerface/config.yaml`

If none exists the CLI runs with defaults (every value unset). Errors carry
the path and the reason:

```text
config: /path/to/config.yaml: not found (--config): os: open_read ...
```

## Values: flags > environment > file > defaults

| Value | Environment variable | File field | Default |
| --- | --- | --- | --- |
| Registry URL | `POKERFACE_REGISTRY_URL` | `registry.url` | *(unset)* |
| Registry token | `POKERFACE_REGISTRY_TOKEN` | `registry.token` | *(unset)* |
| Cache directory | `POKERFACE_CACHE_DIR` | `cache_dir` | `git_cache.default_cache_root()` |
| Cache TTL | `POKERFACE_CACHE_TTL` | — | *(disabled)* |
| Cache size limit | `POKERFACE_CACHE_MAX_SIZE` | — | *(disabled)* |

The cache limits are environment-only for now. `POKERFACE_CACHE_TTL` accepts
seconds or `<n>s/m/h/d`; `POKERFACE_CACHE_MAX_SIZE` accepts bytes or
`<n>K/M/G/T` (1024-based). `0` disables either limit. Invalid values are
errors naming the variable (`config: POKERFACE_CACHE_TTL: expected seconds or
<n>s/m/h/d, got 'soon'`). See `docs/spec/cache.md` for enforcement.

Environment variables override file values when set to a non-empty string;
an unset variable leaves the file value in place. Invalid environment values
are errors naming the variable (`config: POKERFACE_REGISTRY_URL: must start
with https:// or http://`).

## File format

```yaml
registry:
  url: https://registry.example.com
  token: pf_your_token_here
cache_dir: /custom/cache
```

| Field | Type | Required | Validation |
| --- | --- | --- | --- |
| `registry` | mapping | no | known fields: `url`, `token` |
| `registry.url` | string | no | non-empty, must start with `https://` (or `http://` for a local development registry) |
| `registry.token` | string | no | non-empty |
| `cache_dir` | string | no | non-empty |

Unknown fields are rejected with the field's path
(`config: <path>: registry.bogus: unknown field …`) — the same strictness as
`pokerface.yaml`. Invalid YAML names the path and the parser's reason.

## Permissions

When the loaded config file is readable by group or others, the CLI emits a
warning:

```text
warning: config file <path> is readable by group or others (mode 644) — chmod 600 recommended
```

The check uses `stat` (BSD on macOS, GNU on Linux) through the command
runner; a failed stat produces no warning rather than a failed load.
Warnings surface in `settings.summary()` and later in `--verbose` logging
(T1.16).

## Secrets and logging

**Tokens never appear in logs.** `settings.redact(secret)` renders a secret
as `<redacted:<length>>` — length only, never any character of the value —
and `settings.summary(settings)` redacts `registry_token` while printing
everything else in the clear. The redaction contract is pinned by
`test_redact_never_shows_secret` and `test_summary_redacts_token`; T1.16's
verbose logging consumes these helpers and adds header/URL redaction.
