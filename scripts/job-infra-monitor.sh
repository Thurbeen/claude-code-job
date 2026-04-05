#!/usr/bin/env bash
# job-infra-monitor.sh — Monitors Kubernetes cluster health and creates fix PRs via Claude Code.
#
# Required env vars:
#   GH_TOKEN                 - GitHub PAT with repo scope
#   CLAUDE_CODE_OAUTH_TOKEN  - Claude Max OAuth token
#   REPO                     - GitOps repo to clone and fix (owner/repo)
#   PROMETHEUS_URL           - Prometheus endpoint URL
#
# Optional env vars:
#   CLAUDE_PROMPT            - Override default Claude prompt
#   ALLOWED_TOOLS            - Override allowed tools (default: Bash,Read,Glob,Grep,Edit,Write)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_env GH_TOKEN CLAUDE_CODE_OAUTH_TOKEN REPO PROMETHEUS_URL
setup_git

collect_cluster_state() {
  printf '=== Non-Running Pods ===\n'
  kubectl get pods -A --field-selector 'status.phase!=Running,status.phase!=Succeeded' 2>&1 || true

  printf '\n=== Recent Warning Events ===\n'
  kubectl get events -A --field-selector type=Warning --sort-by='.lastTimestamp' 2>&1 | tail -50 || true

  printf '\n=== Node Status ===\n'
  kubectl get nodes -o wide 2>&1 || true
  kubectl top nodes 2>&1 || true

  printf '\n=== Pod Resource Usage (top 20 by memory) ===\n'
  kubectl top pods -A --sort-by=memory 2>&1 | head -20 || true

  printf '\n=== Prometheus Alerts Firing ===\n'
  curl -sf "${PROMETHEUS_URL}/api/v1/alerts" \
    | jq -r '
        .data.alerts[]
        | select(.state=="firing")
        | "\(.labels.alertname) [\(.labels.severity)] - \(.annotations.summary // .annotations.description // "no description")"
      ' 2>/dev/null || true

  printf '\n=== High Restart Count Pods (>3) ===\n'
  kubectl get pods -A -o json \
    | jq -r '
        .items[]
        | select(.status.containerStatuses[]?.restartCount > 3)
        | "\(.metadata.namespace)/\(.metadata.name) restarts=\(.status.containerStatuses[].restartCount)"
      ' 2>/dev/null || true
}

cluster_has_issues() {
  local state="$1"
  # Check for non-running pods (skip header line)
  if echo "$state" | sed -n '/^=== Non-Running Pods ===/,/^$/p' | grep -qv '^\(===\|No resources\|NAMESPACE\|$\)'; then
    return 0
  fi
  # Check for firing alerts
  if echo "$state" | sed -n '/^=== Prometheus Alerts Firing ===/,/^$/p' | grep -qv '^\(===\|$\)'; then
    return 0
  fi
  return 1
}

create_fix_pr() {
  local state="$1"

  local workdir
  workdir=$(mktemp -d)
  gh repo clone "$REPO" "$workdir" -- --depth=1
  cd "$workdir" || return 1

  local branch
  branch="fix/infra-monitor-$(date +%Y%m%d-%H%M%S)"
  git checkout -b "$branch"

  inject_skill "infra-monitor" "$workdir"

  local prompt
  prompt="You are a Kubernetes cluster monitor for a bare-metal Talos Linux cluster managed by ArgoCD GitOps.

Here is the current cluster state:

${state}

Analyze the cluster state above and identify any issues that can be fixed via GitOps changes in this repo.
Focus on:
- Pods in CrashLoopBackOff, Error, or Pending state
- Firing Prometheus alerts that indicate misconfigurations
- Resource limit/request mismatches causing OOMKills
- Any configuration issues visible in events

For each fixable issue, make the minimal targeted change in the appropriate Kubernetes manifest.
Do not refactor unrelated code. Do not fix issues that require manual intervention outside GitOps.
If there are no GitOps-fixable issues, do nothing.

After making changes, stage them with git add."

  run_claude "$prompt" || die "Claude failed"

  if git diff --cached --quiet; then
    log "No GitOps-fixable issues found"
    return 0
  fi

  git commit -m "fix: infra-monitor auto-remediation $(date +%Y-%m-%d)"
  git push -u origin "$branch"
  gh pr create \
    --repo "$REPO" \
    --title "fix: infra-monitor auto-remediation $(date +%Y-%m-%d)" \
    --body "## Automated cluster remediation

This PR was created by the infra-monitor CronJob after detecting issues in the cluster.
Review the changes carefully before merging."

  log "PR created"
}

# Main
log "Collecting cluster state"
STATE=$(collect_cluster_state)

if ! cluster_has_issues "$STATE"; then
  log "Cluster healthy, no action needed"
  exit 0
fi

log "Issues detected, cloning ${REPO}"
create_fix_pr "$STATE"
log "Done"
