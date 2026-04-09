# claude-code-job

A Docker image that packages Claude Code CLI with tooling for running automated jobs. The image provides the **runtime environment and entrypoint** — skills and prompts are injected at deployment time.

Skills are maintained separately in [thurbeen-skills](https://github.com/Thurbeen/thurbeen-skills).

## Quick start

```bash
docker pull ghcr.io/thurbeen/claude-code-job:latest

docker run --rm \
  -e CLAUDE_CODE_OAUTH_TOKEN \
  -e CLAUDE_PROMPT="Hello, what can you help me with?" \
  ghcr.io/thurbeen/claude-code-job:latest
```

## What's included

The Docker image (`node:24-bookworm` base) bundles:

| Tool | Purpose |
|------|---------|
| `claude` | Claude Code CLI |
| `gh` | GitHub CLI |
| `git` | Version control |
| `kubectl` | Kubernetes CLI |
| `curl`, `jq`, `yq` | HTTP requests & data processing |
| `ripgrep`, `fd-find`, `fzf` | Fast file search |
| `python3`, `uv` | Python runtime & package manager |
| `build-essential` | Build toolchain |

## Entrypoint

The image uses `entrypoint.sh` as its entrypoint. It handles:

- **Skill cloning** — set `SKILLS_REPO` + `SKILL_NAME` to clone a skill from GitHub at startup
- **Skill injection** — mount a `CLAUDE.md` file at `CONFIG_DIR` to inject project-level instructions
- **MCP config** — mount `mcp-config.json` at `CONFIG_DIR` for MCP server auto-discovery
- **Prompt** — mount `prompt.txt` at `CONFIG_DIR` or set `CLAUDE_PROMPT` env var
- **Session persistence** — mount `PERSIST_DIR` for conversation continuity across runs
- **OAuth refresh** — automatically refreshes Google OAuth tokens if configured

### Environment variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `CLAUDE_CODE_OAUTH_TOKEN` | Yes | — | Claude Max OAuth token |
| `CONFIG_DIR` | No | `/etc/claude-code-job` | Config mount path |
| `PERSIST_DIR` | No | `/var/lib/claude-code-job` | Persistent storage path |
| `CLAUDE_PROMPT` | No | — | Fallback prompt if no `prompt.txt` mounted |
| `CLAUDE_MODEL` | No | — | Override Claude model |
| `ALLOWED_TOOLS` | No | `Bash,Read,Glob,Grep,Edit,Write` | Override allowed tools |
| `SKILLS_REPO` | No | — | GitHub repo to clone skills from (e.g. `owner/repo`) |
| `SKILL_NAME` | No | — | Skill directory to install from `SKILLS_REPO` |
| `SKILLS_REF` | No | `main` | Git ref/tag to checkout from `SKILLS_REPO` |

### Example with skill from GitHub

```bash
docker run --rm \
  -e CLAUDE_CODE_OAUTH_TOKEN \
  -e GH_TOKEN \
  -e SKILLS_REPO=Thurbeen/thurbeen-skills \
  -e SKILL_NAME=bump-pr-fixer \
  -e CLAUDE_PROMPT="Run the bump-pr-fixer skill" \
  -v claude-data:/var/lib/claude-code-job \
  ghcr.io/thurbeen/claude-code-job:latest
```

### Example with mounted config

```bash
docker run --rm \
  -e CLAUDE_CODE_OAUTH_TOKEN \
  -e GH_TOKEN \
  -v ./my-job-config:/etc/claude-code-job:ro \
  ghcr.io/thurbeen/claude-code-job:latest
```

Where `my-job-config/` contains:
- `CLAUDE.md` — project-level instructions for Claude
- `prompt.txt` — the prompt to run
- `mcp-config.json` — (optional) MCP server configuration

### Persistent sessions

Mount a volume at `PERSIST_DIR` to resume conversations:

```bash
docker run --rm \
  -e CLAUDE_CODE_OAUTH_TOKEN \
  -e CLAUDE_PROMPT="Continue monitoring" \
  -v claude-data:/var/lib/claude-code-job \
  ghcr.io/thurbeen/claude-code-job:latest
```

## Development

### Build locally

```bash
docker build -t claude-code-job .
```

### Pre-commit hooks

```bash
pre-commit install
pre-commit install --hook-type commit-msg
```

### CI/CD

- **CI** runs on every push and PR to `main`: Dockerfile linting (hadolint), shell linting (shellcheck), secret detection (gitleaks), and Docker build.
- **CD** runs on push to `main`: uses cocogitto to auto-bump semver from conventional commits, creates a git tag, builds and pushes the image to `ghcr.io/thurbeen/claude-code-job`, and publishes a GitHub Release.

## License

[Apache-2.0](LICENSE)
