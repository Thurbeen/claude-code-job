# CLAUDE.md

This file provides guidance to Claude Code when working with
this repository.

## What This Is

A Docker image (`ghcr.io/thurbeen/claude-code-job`) that
packages Claude Code CLI with tooling for running automated
jobs. The image provides the runtime environment and
entrypoint — skills and prompts are injected at deployment
time via mounted config files.

## Structure

- `Dockerfile` — Image definition (node:24-bookworm base)
- `scripts/entrypoint.sh` — Generic Claude Code agent entrypoint
- `.github/workflows/ci.yml` — CI (lint, build, secret detection)
- `.github/workflows/cd.yml` — CD (semver release, Docker push)
- `cog.toml` — Cocogitto config for semver releases

## Build & Lint

```bash
docker build -t claude-code-job .
hadolint Dockerfile
shellcheck scripts/entrypoint.sh
```

## Pre-commit Hooks

Pre-commit is configured with: gitleaks, cocogitto
(conventional commits), shellcheck, and hadolint.

```bash
pre-commit install
pre-commit install --hook-type commit-msg
```

## Conventional Commits

All commits must follow
[Conventional Commits](https://www.conventionalcommits.org/).
Enforced by pre-commit hooks and CI.

- **Types**: feat, fix, perf, refactor, docs, style, test,
  chore, ci, build, revert
