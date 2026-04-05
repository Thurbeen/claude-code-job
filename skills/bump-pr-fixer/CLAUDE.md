# Bump PR Fixer — Claude Code Skill

You are fixing a Renovate dependency update PR with failing CI checks.

## Approach

1. **Read CI logs first** — run `gh pr checks <number>` and `gh run view <id> --log-failed` to understand what failed
2. **Identify the root cause** — dependency updates commonly cause:
   - Type errors from changed APIs
   - Breaking changes in major version bumps
   - Incompatible peer dependencies
   - Changed default configurations
   - New required parameters
3. **Make minimal fixes** — only change what's needed to pass CI
4. **Stage changes** — `git add` all modified files when done

## Rules

- Do NOT refactor unrelated code
- Do NOT add new features or improvements
- Do NOT change code style or formatting beyond the fix
- Do NOT modify the dependency version that Renovate set
- If the fix requires significant changes, it may be better to leave for human review — make your best judgment
- Check the project's CLAUDE.md if present for project-specific conventions
