# claude-code-job

A collection of ready-to-use Claude Code jobs packaged in a Docker image.

Each job is a self-contained script that uses Claude Code CLI to automate a specific development task. The image ships with all the tools needed to clone repos, run CI diagnostics, and push fixes — no extra setup required.

## What's included

The Docker image (`node:24-bookworm` base) bundles:

| Tool | Purpose |
|------|---------|
| `claude` | Claude Code CLI |
| `gh` | GitHub CLI |
| `git` | Version control |
| `curl`, `jq`, `yq` | HTTP requests & data processing |
| `ripgrep`, `fd-find`, `fzf` | Fast file search |
| `python3`, `build-essential` | Build toolchain |
| `openssh-client` | SSH access |

## Quick start

```bash
docker pull ghcr.io/thurbeen/claude-code-job:latest

docker run --rm \
  -e GH_TOKEN \
  -e CLAUDE_CODE_OAUTH_TOKEN \
  ghcr.io/thurbeen/claude-code-job:latest \
  /usr/local/share/claude-code-job/scripts/renovate-pr-fixer.sh
```

## Jobs

All job scripts live in `/usr/local/share/claude-code-job/scripts/` inside the image.

### renovate-pr-fixer

Finds open Renovate PRs with failing CI checks, uses Claude Code to diagnose and fix them, then pushes the fix back to the PR branch.

**Required environment variables:**

| Variable | Description |
|----------|-------------|
| `GH_TOKEN` | GitHub PAT with repo scope |
| `CLAUDE_CODE_OAUTH_TOKEN` | Claude Max OAuth token |
| `REPOS` | Newline-separated list of `owner/repo` to process |

**Example:**

```bash
docker run --rm \
  -e GH_TOKEN="ghp_..." \
  -e CLAUDE_CODE_OAUTH_TOKEN="..." \
  -e REPOS=$'owner/repo-one\nowner/repo-two' \
  ghcr.io/thurbeen/claude-code-job:latest \
  /usr/local/share/claude-code-job/scripts/renovate-pr-fixer.sh
```

## Development

### Build locally

```bash
docker build -t claude-code-job .
```

### Pre-commit hooks

The repo uses pre-commit with hadolint, shellcheck, gitleaks, and conventional commit validation. Install hooks with:

```bash
pre-commit install
```

### CI/CD

- **CI** runs on every push and PR to `main`: Dockerfile linting, shell linting, secret detection, and image build.
- **CD** runs on push to `main`: builds and pushes the image to `ghcr.io/thurbeen/claude-code-job` tagged with the short SHA and `latest`.
