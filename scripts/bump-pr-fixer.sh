#!/usr/bin/env bash
set -euo pipefail

# bump-pr-fixer.sh
# Finds Renovate PRs with failing CI and uses Claude Code to fix them.
#
# Required env vars:
#   GH_TOKEN                 - GitHub PAT with repo scope
#   CLAUDE_CODE_OAUTH_TOKEN  - Claude Max OAuth token
#   REPOS                    - Newline-separated list of owner/repo
#
# Optional env vars:
#   CLAUDE_PROMPT            - Override default Claude prompt
#   ALLOWED_TOOLS            - Override default allowed tools (default: Bash,Read,Glob,Grep,Edit,Write)

: "${GH_TOKEN:?GH_TOKEN is required}"
: "${CLAUDE_CODE_OAUTH_TOKEN:?CLAUDE_CODE_OAUTH_TOKEN is required}"
: "${REPOS:?REPOS is required}"

SKILLS_DIR="/usr/local/share/claude-code-job/skills/bump-pr-fixer"
ALLOWED_TOOLS="${ALLOWED_TOOLS:-Bash,Read,Glob,Grep,Edit,Write}"

# Configure git identity
git config --global user.name "claude-code-bot"
git config --global user.email "claude-code-bot@users.noreply.github.com"

# Configure git auth via GH_TOKEN
git config --global url."https://x-access-token:${GH_TOKEN}@github.com/".insteadOf "https://github.com/"

# Read repo list (one per line, skip blanks and comments)
while IFS= read -r repo; do
  [[ -z "$repo" || "$repo" == \#* ]] && continue
  echo "=== Processing ${repo} ==="

  # List open PRs by renovate with failed checks
  failed_prs=$(gh pr list \
    --repo "$repo" \
    --author "app/renovate" \
    --state open \
    --json number,headRefName,statusCheckRollup \
    --jq '[.[] | select(.statusCheckRollup[]? | .status == "COMPLETED" and .conclusion == "FAILURE")] | unique_by(.number) | .[].number' \
  ) || true

  if [[ -z "$failed_prs" ]]; then
    echo "No failed Renovate PRs in ${repo}"
    continue
  fi

  # Clone repo once
  repo_dir="/workspace/$(echo "$repo" | tr '/' '-')"
  gh repo clone "$repo" "$repo_dir"

  for pr_number in $failed_prs; do
    echo "--- Fixing PR #${pr_number} in ${repo} ---"
    cd "$repo_dir"
    git checkout main && git pull

    # Checkout PR branch
    gh pr checkout "$pr_number"

    # Inject skills CLAUDE.md if available
    if [[ -f "${SKILLS_DIR}/CLAUDE.md" ]]; then
      cp "${SKILLS_DIR}/CLAUDE.md" "$repo_dir/CLAUDE.md"
    fi

    # Build prompt
    DEFAULT_PROMPT="This is a Renovate dependency update PR (${repo}#${pr_number}) with failing CI checks. \
Diagnose why CI is failing and fix the issue. \
The failure is likely caused by the dependency update requiring code changes. \
Look at CI logs, test failures, and type errors. \
Make minimal targeted fixes - do not refactor unrelated code. \
After fixing, stage your changes with git add."

    PROMPT="${CLAUDE_PROMPT:-$DEFAULT_PROMPT}"

    # Run Claude Code to diagnose and fix
    claude -p "$PROMPT" \
      --allowedTools "$ALLOWED_TOOLS" \
    || { echo "Claude failed on PR #${pr_number}, skipping"; cd /workspace; continue; }

    # Amend the last commit and force-push
    if ! git diff --cached --quiet; then
      branch=$(git branch --show-current)
      git commit --amend --no-edit
      git push --force-with-lease origin "$branch"
      echo "Pushed fix for PR #${pr_number}"
    else
      echo "No changes made for PR #${pr_number}"
    fi

    cd /workspace
  done

  # Cleanup
  rm -rf "$repo_dir"
done <<< "$REPOS"

echo "=== Done ==="
