# GitLab CI (T4.6)

The minimal `.gitlab-ci.yml` for a repository carrying a `pokerface.yaml`.
Same trigger contract as ADR 0001: branch pushes, `v*` tags, and manual
runs (GitLab's `web` pipeline source). The lock commit's message carries
`[skip ci]`, which GitLab honors — the lock write-back never re-triggers
the pipeline. The registry token is a masked, protected CI variable, so it
only ever lives in the job's environment.

```yaml
# .gitlab-ci.yml — publish with pokerface (ADR 0001)
stages: [publish]

publish:
  stage: publish
  # The build runs buildx; the dind service provides it.
  image: docker:24
  services: ["docker:24-dind"]
  variables:
    POKERFACE_REGISTRY_TOKEN: "$POKERFACE_REGISTRY_TOKEN" # masked + protected
    POKERFACE_VERSION: "v0.1.0"
    GIT_DEPTH: "0" # the tag/branch facts the renderer needs
  rules:
    - if: "$CI_COMMIT_TAG =~ /^v/"
    - if: "$CI_COMMIT_BRANCH && $CI_PIPELINE_SOURCE == \"push\""
    - if: "$CI_PIPELINE_SOURCE == \"web\""
  before_script:
    - apk add --no-cache curl git
    - curl -fsSL "https://raw.githubusercontent.com/daqing/pokerface/main/install.sh" | sh
  script:
    - pokerface build --write-lock
    - git config user.name "pokerface-ci"
    - git config user.email "pokerface-ci@users.noreply.gitlab.com"
    - git add pokerface.lock.yaml
    - |
      if git diff --cached --quiet; then
        echo "the lock did not change"
      else
        git commit -m "pokerface: update pokerface.lock.yaml [skip ci]"
        # A project access token with write_repository, masked + protected.
        git push "https://pokerface-ci:${POKERFACE_LOCK_PUSH_TOKEN}@${CI_SERVER_HOST}/${CI_PROJECT_PATH}.git" "HEAD:${CI_COMMIT_REF_NAME}"
      fi
```

Setup:

1. **`POKERFACE_REGISTRY_TOKEN`** — a CI/CD variable (masked, protected)
   holding a registry token with the push scope for the image's repository
   (`docs/spec/push.md`). The CLI reads it from the environment.
2. **`POKERFACE_LOCK_PUSH_TOKEN`** — a project access token with
   `write_repository`, also masked and protected, used only for the lock
   push back to Git.
3. `GIT_DEPTH: "0"` — `git describe --tags --abbrev=0` and the exact-match
   tag detection need the tags.

Notes:

- GitLab honors `[ci skip]` / `[skip ci]` in the commit message, so the
  lock commit does not re-trigger the pipeline.
- The dind service is required only because the build adapter shells out to
  `docker buildx`. A runner with a real Docker socket can drop the service
  and use `image: docker:24` with the socket mounted.
- On protected branches, make both variables protected too, or the lock
  push fails with an authentication error (see `docs/TASKS.md` T4.15).
