# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A Docker image (`ghcr.io/thurbeen/claude-code-job`) that packages Claude Code CLI with tooling for automated CI-fix workflows. The primary use case is the `renovate-pr-fixer` script, which finds Renovate PRs with failing CI and runs Claude Code to diagnose and fix them.

## Build & Lint

```bash
# Build the Docker image
docker build -t claude-code-job .

# Lint Dockerfile
hadolint Dockerfile

# Lint shell scripts
shellcheck scripts/*.sh

# Run gitleaks secret detection
gitleaks detect --source . --verbose
```

## Pre-commit Hooks

Pre-commit is configured with: gitleaks, conventional-pre-commit (commit messages must follow Conventional Commits), shellcheck, and hadolint. Run `pre-commit install` and `pre-commit install --hook-type commit-msg` to set up.

## CI/CD

- **CI** (`ci.yml`): Runs hadolint, shellcheck, gitleaks, and a Docker build (no push) on PRs and pushes to main. The `all-checks` job gates mergeability.
- **CD** (`cd.yml`): On push to main, builds and pushes the image to `ghcr.io/thurbeen/claude-code-job` tagged with short SHA and `latest`.

## Key Files

- `Dockerfile` — Image definition: node:24-bookworm base, installs git/curl/jq/ripgrep/fd/fzf/gh/yq/python3/build-essential, then `@anthropic-ai/claude-code`. Copies scripts into `/usr/local/share/claude-code-job/scripts/`.
- `scripts/renovate-pr-fixer.sh` — Main automation script. Requires `GH_TOKEN`, `CLAUDE_CODE_OAUTH_TOKEN`, and `REPOS` env vars. Iterates repos, finds failed Renovate PRs, checks out each branch, runs Claude Code in print mode to fix, then amends and force-pushes.

## Conventions

- Commit messages must follow [Conventional Commits](https://www.conventionalcommits.org/).
- Renovate manages dependency updates with automerge enabled. GitHub Actions pins use digest pinning.
- Hadolint ignores DL3008 (apt version pinning) and DL3016 (npm version pinning) — these are managed by Renovate via base image bumps.
