#!/usr/bin/env bash
# job-mcp-agent.sh — Generic Claude Code agent with configurable MCPs.
#
# MCP config, skill (CLAUDE.md), and prompt are injected via mounted files
# at CONFIG_DIR (default: /etc/claude-code-job/).
#
# Supports persistent sessions when PERSIST_DIR is mounted:
#   - Resumes previous conversation with --continue
#   - Caches npm/uv packages across runs
#
# Required env vars:
#   CLAUDE_CODE_OAUTH_TOKEN  - Claude Max OAuth token
#
# Optional env vars:
#   CONFIG_DIR               - Override config mount path (default: /etc/claude-code-job)
#   PERSIST_DIR              - Persistent storage path (default: /var/lib/claude-code-job)
#   CLAUDE_PROMPT            - Override prompt (fallback if no prompt.txt mounted)
#   ALLOWED_TOOLS            - Override allowed tools

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

CONFIG_DIR="${CONFIG_DIR:-/etc/claude-code-job}"
PERSIST_DIR="${PERSIST_DIR:-/var/lib/claude-code-job}"
ALLOWED_TOOLS="${ALLOWED_TOOLS:-Bash,Read,Glob,Grep,Edit,Write}"

require_env CLAUDE_CODE_OAUTH_TOKEN

# Set up persistent caches if storage is mounted
if [[ -d "$PERSIST_DIR" ]]; then
  log "Persistent storage detected at ${PERSIST_DIR}"

  # Package caches (npm, uv)
  export npm_config_cache="${PERSIST_DIR}/cache/npm"
  export UV_CACHE_DIR="${PERSIST_DIR}/cache/uv"
  mkdir -p "$npm_config_cache" "$UV_CACHE_DIR"

  # Claude session data
  export CLAUDE_CONFIG_DIR="${PERSIST_DIR}/claude"
  mkdir -p "$CLAUDE_CONFIG_DIR"

  # Use a fixed workdir so --continue finds the previous session
  WORKDIR="${PERSIST_DIR}/workspace"
  mkdir -p "$WORKDIR"
else
  log "No persistent storage, using ephemeral workdir"
  WORKDIR=$(mktemp -d)
fi

# Refresh Google OAuth access token if refresh token is available
if [[ -n "${GOOGLE_REFRESH_TOKEN:-}" && -n "${GOOGLE_CLIENT_ID:-}" && -n "${GOOGLE_CLIENT_SECRET:-}" ]]; then
  log "Refreshing Google OAuth access token"
  GOOGLE_ACCESS_TOKEN=$(curl -sf -X POST https://oauth2.googleapis.com/token \
    -d "client_id=${GOOGLE_CLIENT_ID}" \
    -d "client_secret=${GOOGLE_CLIENT_SECRET}" \
    -d "refresh_token=${GOOGLE_REFRESH_TOKEN}" \
    -d "grant_type=refresh_token" | jq -r '.access_token')
  if [[ -n "$GOOGLE_ACCESS_TOKEN" && "$GOOGLE_ACCESS_TOKEN" != "null" ]]; then
    export GOOGLE_ACCESS_TOKEN
    log "Google access token refreshed"
  else
    warn "Failed to refresh Google access token"
  fi
fi

cd "$WORKDIR" || die "Failed to cd into ${WORKDIR}"

# Inject skill if mounted
if [[ -f "${CONFIG_DIR}/CLAUDE.md" ]]; then
  cp "${CONFIG_DIR}/CLAUDE.md" "${WORKDIR}/CLAUDE.md"
  log "Injected skill from ${CONFIG_DIR}/CLAUDE.md"
fi

# Place MCP config as .mcp.json in workdir for auto-discovery
if [[ -f "${CONFIG_DIR}/mcp-config.json" ]]; then
  cp "${CONFIG_DIR}/mcp-config.json" "${WORKDIR}/.mcp.json"
  log "Placed MCP config at ${WORKDIR}/.mcp.json"
fi

# Read prompt
if [[ -f "${CONFIG_DIR}/prompt.txt" ]]; then
  PROMPT=$(cat "${CONFIG_DIR}/prompt.txt")
elif [[ -n "${CLAUDE_PROMPT:-}" ]]; then
  PROMPT="$CLAUDE_PROMPT"
else
  die "No prompt found: mount prompt.txt or set CLAUDE_PROMPT"
fi

# Build claude args
# Use --continue to resume previous session if persistent storage is available
if [[ -d "$PERSIST_DIR" ]]; then
  CLAUDE_ARGS=(-c -p "$PROMPT" --allowedTools "$ALLOWED_TOOLS")
  log "Running Claude with session continuity"
else
  CLAUDE_ARGS=(-p "$PROMPT" --allowedTools "$ALLOWED_TOOLS")
  log "Running Claude (ephemeral session)"
fi

# Optional model override
if [[ -n "${CLAUDE_MODEL:-}" ]]; then
  CLAUDE_ARGS+=(--model "$CLAUDE_MODEL")
  log "Using model: ${CLAUDE_MODEL}"
fi

claude "${CLAUDE_ARGS[@]}"
log "Done"
