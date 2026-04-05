#!/usr/bin/env bash
# job-bump-pr-fixer.sh — Finds Renovate PRs with failing CI and uses Claude Code to fix them.
#
# Required env vars:
#   GH_TOKEN                 - GitHub PAT with repo scope
#   CLAUDE_CODE_OAUTH_TOKEN  - Claude Max OAuth token
#   REPOS                    - Newline-separated list of owner/repo
#
# Optional env vars:
#   CLAUDE_PROMPT            - Override default Claude prompt
#   ALLOWED_TOOLS            - Override allowed tools (default: Bash,Read,Glob,Grep,Edit,Write)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_env GH_TOKEN CLAUDE_CODE_OAUTH_TOKEN REPOS
setup_git

find_failed_renovate_prs() {
  local repo="$1"
  gh pr list \
    --repo "$repo" \
    --author "app/renovate" \
    --state open \
    --json number,statusCheckRollup \
    --jq '
      [.[] | select(.statusCheckRollup[]? | .status == "COMPLETED" and .conclusion == "FAILURE")]
      | unique_by(.number)
      | .[].number
    ' 2>/dev/null || true
}

fix_pr() {
  local repo="$1" pr_number="$2" repo_dir="$3"

  log "Fixing PR #${pr_number} in ${repo}"
  cd "$repo_dir" || return 1
  git checkout main && git pull --quiet
  gh pr checkout "$pr_number"

  inject_skill "bump-pr-fixer" "$repo_dir"

  local prompt="This is a Renovate dependency update PR (${repo}#${pr_number}) with failing CI checks. \
Diagnose why CI is failing and fix the issue. \
The failure is likely caused by the dependency update requiring code changes. \
Look at CI logs, test failures, and type errors. \
Make minimal targeted fixes - do not refactor unrelated code. \
After fixing, stage your changes with git add."

  if ! run_claude "$prompt"; then
    warn "Claude failed on PR #${pr_number}, skipping"
    return 1
  fi

  if git diff --cached --quiet; then
    log "No changes needed for PR #${pr_number}"
    return 0
  fi

  local branch
  branch=$(git branch --show-current)
  git commit --amend --no-edit
  git push --force-with-lease origin "$branch"
  log "Pushed fix for PR #${pr_number}"
}

# Main loop
while IFS= read -r repo; do
  [[ -z "$repo" || "$repo" == \#* ]] && continue
  log "Processing ${repo}"

  failed_prs=$(find_failed_renovate_prs "$repo")
  if [[ -z "$failed_prs" ]]; then
    log "No failed Renovate PRs in ${repo}"
    continue
  fi

  repo_dir="/workspace/$(echo "$repo" | tr '/' '-')"
  gh repo clone "$repo" "$repo_dir"

  for pr_number in $failed_prs; do
    (fix_pr "$repo" "$pr_number" "$repo_dir") || true
  done

  rm -rf "$repo_dir"
done <<< "$REPOS"

log "Done"
