#!/usr/bin/env bash
# entrypoint.sh — Generic Claude Code agent with configurable skills and MCPs.
#
# Skills, MCP config, and prompt are injected via mounted files
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
#   CLAUDE_MODEL             - Override Claude model
#   ALLOWED_TOOLS            - Override allowed tools
#   SKILLS_REPO              - GitHub repo to clone skills from (e.g. owner/repo)
#   SKILL_NAME               - Skill directory to install from SKILLS_REPO
#   SKILLS_REF               - Git ref to checkout (default: main)

set -euo pipefail

CONFIG_DIR="${CONFIG_DIR:-/etc/claude-code-job}"
PERSIST_DIR="${PERSIST_DIR:-/var/lib/claude-code-job}"
ALLOWED_TOOLS="${ALLOWED_TOOLS:-Bash,Read,Glob,Grep,Edit,Write}"

# --- Logging ---

log()  { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }
warn() { log "WARN: $*"; }
die()  { log "FATAL: $*"; exit 1; }

# --- Validation ---

[[ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]] || die "Missing required env var: CLAUDE_CODE_OAUTH_TOKEN"

# --- Persistent storage ---

if [[ -d "$PERSIST_DIR" ]]; then
  log "Persistent storage detected at ${PERSIST_DIR}"

  export npm_config_cache="${PERSIST_DIR}/cache/npm"
  export UV_CACHE_DIR="${PERSIST_DIR}/cache/uv"
  mkdir -p "$npm_config_cache" "$UV_CACHE_DIR"

  export CLAUDE_CONFIG_DIR="${PERSIST_DIR}/claude"
  mkdir -p "$CLAUDE_CONFIG_DIR"

  WORKDIR="${PERSIST_DIR}/workspace"
  mkdir -p "$WORKDIR"
else
  log "No persistent storage, using ephemeral workdir"
  WORKDIR=$(mktemp -d)
fi

# --- OAuth token refresh ---

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

# --- Skill cloning ---

if [[ -n "${SKILLS_REPO:-}" && -n "${SKILL_NAME:-}" ]]; then
  SKILLS_REF="${SKILLS_REF:-main}"
  SKILLS_DIR="${PERSIST_DIR}/skills-repo"

  if [[ -d "${SKILLS_DIR}/.git" ]]; then
    log "Updating skills repo"
    git -C "$SKILLS_DIR" fetch --depth=1 origin "$SKILLS_REF" 2>&1 >&2
    git -C "$SKILLS_DIR" checkout FETCH_HEAD 2>&1 >&2
  else
    log "Cloning skills from ${SKILLS_REPO} (ref: ${SKILLS_REF})"
    rm -rf "$SKILLS_DIR"
    git clone --depth=1 --branch "$SKILLS_REF" \
      "https://github.com/${SKILLS_REPO}.git" "$SKILLS_DIR" 2>&1 >&2
  fi

  SKILL_SRC="${SKILLS_DIR}/skills/${SKILL_NAME}"
  if [[ -d "$SKILL_SRC" ]]; then
    SKILL_DEST="${HOME}/.claude/skills/${SKILL_NAME}"
    mkdir -p "$(dirname "$SKILL_DEST")"
    ln -sfn "$SKILL_SRC" "$SKILL_DEST"
    log "Installed skill: ${SKILL_NAME} -> ${SKILL_DEST}"
  else
    die "Skill '${SKILL_NAME}' not found in ${SKILLS_REPO}"
  fi
fi

# --- Skill injection (from mounted config) ---

if [[ -f "${CONFIG_DIR}/CLAUDE.md" ]]; then
  cp "${CONFIG_DIR}/CLAUDE.md" "${WORKDIR}/CLAUDE.md"
  log "Injected CLAUDE.md from ${CONFIG_DIR}"
fi

# --- MCP config ---

if [[ -f "${CONFIG_DIR}/mcp-config.json" ]]; then
  cp "${CONFIG_DIR}/mcp-config.json" "${WORKDIR}/.mcp.json"
  log "Placed MCP config at ${WORKDIR}/.mcp.json"
fi

# --- Prompt ---

if [[ -f "${CONFIG_DIR}/prompt.txt" ]]; then
  PROMPT=$(cat "${CONFIG_DIR}/prompt.txt")
elif [[ -n "${CLAUDE_PROMPT:-}" ]]; then
  PROMPT="$CLAUDE_PROMPT"
else
  die "No prompt found: mount prompt.txt or set CLAUDE_PROMPT"
fi

# --- Run Claude ---

CLAUDE_ARGS=(-p "$PROMPT" --allowedTools "$ALLOWED_TOOLS")

if [[ -d "$PERSIST_DIR" ]]; then
  CLAUDE_ARGS=(-c "${CLAUDE_ARGS[@]}")
  log "Running Claude with session continuity"
else
  log "Running Claude (ephemeral session)"
fi

if [[ -n "${CLAUDE_MODEL:-}" ]]; then
  CLAUDE_ARGS+=(--model "$CLAUDE_MODEL")
  log "Using model: ${CLAUDE_MODEL}"
fi

claude "${CLAUDE_ARGS[@]}"
log "Done"
