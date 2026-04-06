#!/usr/bin/env bash
# job-mcp-agent.sh — Generic Claude Code agent with configurable MCPs.
#
# MCP config, skill (CLAUDE.md), and prompt are injected via mounted files
# at CONFIG_DIR (default: /etc/claude-code-job/).
#
# Required env vars:
#   CLAUDE_CODE_OAUTH_TOKEN  - Claude Max OAuth token
#
# Optional env vars:
#   CONFIG_DIR               - Override config mount path (default: /etc/claude-code-job)
#   CLAUDE_PROMPT            - Override prompt (fallback if no prompt.txt mounted)
#   ALLOWED_TOOLS            - Override allowed tools (default includes mcp__*)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

CONFIG_DIR="${CONFIG_DIR:-/etc/claude-code-job}"
ALLOWED_TOOLS="${ALLOWED_TOOLS:-Bash,Read,Glob,Grep,Edit,Write}"

require_env CLAUDE_CODE_OAUTH_TOKEN

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

WORKDIR=$(mktemp -d)
cd "$WORKDIR" || die "Failed to cd into ${WORKDIR}"

# Inject skill if mounted
if [[ -f "${CONFIG_DIR}/CLAUDE.md" ]]; then
  cp "${CONFIG_DIR}/CLAUDE.md" "${WORKDIR}/CLAUDE.md"
  log "Injected skill from ${CONFIG_DIR}/CLAUDE.md"
fi

# Read prompt
if [[ -f "${CONFIG_DIR}/prompt.txt" ]]; then
  PROMPT=$(cat "${CONFIG_DIR}/prompt.txt")
elif [[ -n "${CLAUDE_PROMPT:-}" ]]; then
  PROMPT="$CLAUDE_PROMPT"
else
  die "No prompt found: mount prompt.txt or set CLAUDE_PROMPT"
fi

# Build claude args: prompt must come right after -p
CLAUDE_ARGS=(-p "$PROMPT" --allowedTools "$ALLOWED_TOOLS")

if [[ -f "${CONFIG_DIR}/mcp-config.json" ]]; then
  CLAUDE_ARGS+=(--mcp-config "${CONFIG_DIR}/mcp-config.json")
  log "Using MCP config from ${CONFIG_DIR}/mcp-config.json"
fi

log "Running Claude with MCP agent"
claude "${CLAUDE_ARGS[@]}"
log "Done"
