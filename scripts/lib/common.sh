#!/usr/bin/env bash
# common.sh — Shared utilities for claude-code-job scripts.
# Source this file: source "$(dirname "$0")/lib/common.sh"

set -euo pipefail

SKILLS_BASE="/usr/local/share/claude-code-job/skills"
ALLOWED_TOOLS="${ALLOWED_TOOLS:-Bash,Read,Glob,Grep,Edit,Write}"

# --- Logging ---

log()  { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }
warn() { log "WARN: $*" >&2; }
die()  { log "FATAL: $*" >&2; exit 1; }

# --- Environment ---

require_env() {
  local var
  for var in "$@"; do
    [[ -n "${!var:-}" ]] || die "Missing required env var: ${var}"
  done
}

# --- Git ---

setup_git() {
  git config --global user.name "claude-code-bot"
  git config --global user.email "claude-code-bot@users.noreply.github.com"
  git config --global url."https://x-access-token:${GH_TOKEN}@github.com/".insteadOf "https://github.com/"
}

# --- Skills ---

# Copies the CLAUDE.md skill file for a given job into a target directory.
# Usage: inject_skill "infra-monitor" "/path/to/repo"
inject_skill() {
  local job="$1" target_dir="$2"
  local skill_file="${SKILLS_BASE}/${job}/CLAUDE.md"
  if [[ -f "$skill_file" ]]; then
    cp "$skill_file" "${target_dir}/CLAUDE.md"
    log "Injected skill: ${job}"
  fi
}

# --- Claude ---

# Runs Claude Code with the given prompt. Falls back to CLAUDE_PROMPT env var if set.
# Usage: run_claude "prompt text"
run_claude() {
  local prompt="${CLAUDE_PROMPT:-$1}"
  claude -p "$prompt" --allowedTools "$ALLOWED_TOOLS"
}
