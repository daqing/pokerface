# Gitea Actions (T4.6)

Gitea Actions speaks the GitHub Actions syntax, so the publish workflow is
the same file (`.gitea/workflows/publish.yaml` or
`.github/workflows/publish.yaml` — Gitea reads both) with two adjustments:
the checkout action comes from the pinned mirror your instance trusts, and
the lock-push credential is a Gitea token secret.

```yaml
# .gitea/workflows/publish.yaml — publish with pokerface (ADR 0001)
name: publish

on:
  push:
    branches: ["**"]
    tags: ["v*"]
    paths-ignore:
      - "pokerface.lock.yaml"
  workflow_dispatch:

jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Install pokerface (pinned)
        if: hashFiles('pokerface.yaml') != ''
        env:
          POKERFACE_VERSION: "v0.1.0"
        run: curl -fsSL "https://raw.githubusercontent.com/daqing/pokerface/main/install.sh" | bash

      - name: Build, push, and write the lock
        if: hashFiles('pokerface.yaml') != ''
        env:
          POKERFACE_REGISTRY_TOKEN: ${{ secrets.POKERFACE_REGISTRY_TOKEN }}
        run: pokerface build --write-lock

      - name: Commit the lock back
        env:
          # A token with repository write, created in the Gitea UI and
          # stored as an organization/repository secret.
          POKERFACE_LOCK_PUSH_TOKEN: ${{ secrets.POKERFACE_LOCK_PUSH_TOKEN }}
        run: |
          git config user.name "pokerface-ci"
          git config user.email "pokerface-ci@users.noreply.gitea.com"
          git add pokerface.lock.yaml
          if git diff --cached --quiet; then
            echo "the lock did not change"
          else
            git commit -m "pokerface: update pokerface.lock.yaml [skip ci]"
            git push "https://pokerface-ci:${POKERFACE_LOCK_PUSH_TOKEN}@${GITEA_SERVER_HOST#/}/${GITHUB_REPOSITORY}.git" "HEAD:${GITHUB_REF_NAME}"
          fi
```

Notes:

- **The loop guard is `paths-ignore`.** Gitea Actions' `[skip ci]` support
  depends on the instance version — do not rely on it; the paths-ignore on
  `pokerface.lock.yaml` is the reliable guard (a commit that only touches
  the lock does not start a pipeline).
- The runner needs Docker + buildx (the `ubuntu-latest` label on a
  gitea-act-runner image provides it).
- Secrets are environment-only: the token reaches the CLI through
  `POKERFACE_REGISTRY_TOKEN` for the single build step and never lands on
  disk or in the lock.
