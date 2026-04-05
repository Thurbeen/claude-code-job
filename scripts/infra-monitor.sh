#!/usr/bin/env bash
set -euo pipefail

# infra-monitor.sh
# Monitors Kubernetes cluster health and uses Claude Code to create fix PRs.
#
# Required env vars:
#   GH_TOKEN                 - GitHub PAT with repo scope
#   CLAUDE_CODE_OAUTH_TOKEN  - Claude Max OAuth token
#   REPO                     - GitOps repo to clone and fix (owner/repo)
#   PROMETHEUS_URL           - Prometheus endpoint URL
#
# Optional env vars:
#   CLAUDE_PROMPT            - Override default Claude prompt
#   ALLOWED_TOOLS            - Override default allowed tools (default: Bash,Read,Glob,Grep,Edit,Write)

: "${GH_TOKEN:?GH_TOKEN is required}"
: "${CLAUDE_CODE_OAUTH_TOKEN:?CLAUDE_CODE_OAUTH_TOKEN is required}"
: "${REPO:?REPO is required}"
: "${PROMETHEUS_URL:?PROMETHEUS_URL is required}"

SKILLS_DIR="/usr/local/share/claude-code-job/skills/infra-monitor"
ALLOWED_TOOLS="${ALLOWED_TOOLS:-Bash,Read,Glob,Grep,Edit,Write}"

# Configure git identity
git config --global user.name "claude-code-bot"
git config --global user.email "claude-code-bot@users.noreply.github.com"

# Configure git auth via GH_TOKEN
git config --global url."https://x-access-token:${GH_TOKEN}@github.com/".insteadOf "https://github.com/"

echo "=== Collecting cluster state ==="

CLUSTER_STATE=$(mktemp)
{
  echo "=== Non-Running Pods ==="
  kubectl get pods -A --field-selector 'status.phase!=Running,status.phase!=Succeeded' 2>&1 || true

  echo -e "\n=== Recent Warning Events ==="
  kubectl get events -A --field-selector type=Warning --sort-by='.lastTimestamp' 2>&1 | tail -50 || true

  echo -e "\n=== Node Status ==="
  kubectl get nodes -o wide 2>&1 || true
  kubectl top nodes 2>&1 || true

  echo -e "\n=== Pod Resource Usage (top 20 by memory) ==="
  kubectl top pods -A --sort-by=memory 2>&1 | head -20 || true

  echo -e "\n=== Prometheus Alerts Firing ==="
  curl -sf "${PROMETHEUS_URL}/api/v1/alerts" \
    | jq -r '.data.alerts[] | select(.state=="firing") | "\(.labels.alertname) [\(.labels.severity)] - \(.annotations.summary // .annotations.description // "no description")"' \
    2>&1 || true

  echo -e "\n=== High Restart Count Pods (>3) ==="
  kubectl get pods -A -o json \
    | jq -r '.items[] | select(.status.containerStatuses[]?.restartCount > 3) | "\(.metadata.namespace)/\(.metadata.name) restarts=\(.status.containerStatuses[].restartCount)"' \
    2>&1 || true
} > "$CLUSTER_STATE"

STATE=$(cat "$CLUSTER_STATE")

# If nothing abnormal, exit early
HAS_BAD_PODS=$(kubectl get pods -A --field-selector 'status.phase!=Running,status.phase!=Succeeded' --no-headers 2>/dev/null || true)
HAS_FIRING_ALERTS=$(curl -sf "${PROMETHEUS_URL}/api/v1/alerts" \
  | jq -r '.data.alerts[] | select(.state=="firing") | .labels.alertname' 2>/dev/null || true)

if [[ -z "$HAS_BAD_PODS" && -z "$HAS_FIRING_ALERTS" ]]; then
  echo "Cluster healthy, no action needed."
  exit 0
fi

echo "=== Issues detected, cloning ${REPO} ==="

# Clone the repo and run Claude Code to fix issues
WORKDIR=$(mktemp -d)
cd "$WORKDIR"
gh repo clone "$REPO" . -- --depth=1

BRANCH="fix/infra-monitor-$(date +%Y%m%d-%H%M%S)"
git checkout -b "$BRANCH"

# Inject skills CLAUDE.md if available
if [[ -f "${SKILLS_DIR}/CLAUDE.md" ]]; then
  cp "${SKILLS_DIR}/CLAUDE.md" "$WORKDIR/CLAUDE.md"
fi

# Build prompt
DEFAULT_PROMPT="You are a Kubernetes cluster monitor for a bare-metal Talos Linux cluster managed by ArgoCD GitOps.

Here is the current cluster state:

${STATE}

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

PROMPT="${CLAUDE_PROMPT:-$DEFAULT_PROMPT}"

claude -p "$PROMPT" \
  --allowedTools "$ALLOWED_TOOLS" \
|| { echo "Claude failed, exiting"; exit 1; }

# Create PR if there are changes
if [ -n "$(git diff --cached --name-only)" ]; then
  git commit -m "fix: infra-monitor auto-remediation $(date +%Y-%m-%d)"
  git push -u origin "$BRANCH"
  gh pr create \
    --repo "$REPO" \
    --title "fix: infra-monitor auto-remediation $(date +%Y-%m-%d)" \
    --body "$(cat <<'EOF'
## Automated cluster remediation

This PR was created by the infra-monitor CronJob after detecting issues in the cluster.
Review the changes carefully before merging.
EOF
)"
  echo "PR created successfully."
else
  echo "No GitOps-fixable issues found."
fi

echo "=== Done ==="
