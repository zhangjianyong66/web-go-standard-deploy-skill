---
name: safe-git-commit-push
description: Safely commit all uncommitted changes in current git repository by scanning for sensitive info before auto-commit and auto-push.
---

# Safe Git Commit + Push

## Overview
This skill updates `.gitignore` with common process-artifact rules, stages all local changes in the current repository, scans staged content for common sensitive data patterns, generates a commit message automatically, then pushes to the current upstream branch.

Default policy: **scan first, then commit, then push**.

## Required Inputs
No required env vars.

## Optional Inputs
- `FALLBACK_COMMIT_PREFIX` default `chore: update`
- `SAFE_SCAN_STRICT` default `0`
  - `0`: balanced policy (recommended)
  - `1`: stricter token-like pattern checks
- `AUTO_UPDATE_GITIGNORE` default `1`
  - `1`: auto-append missing common process-artifact rules into `.gitignore`
  - `0`: skip `.gitignore` update

## Standard Flow
1. `./scripts/safe-commit-push.sh`

## Behavior
1. Verify current path is a git repository.
2. Verify there are uncommitted changes.
3. Update `.gitignore` with missing common process-artifact rules.
4. Stage all changes with `git add -A`.
5. Scan staged changes and staged paths for high-risk patterns.
6. Generate commit message from staged change summary.
7. Commit and push to upstream.

## Guardrails
- Only appends missing ignore rules; does not rewrite existing `.gitignore` structure.
- Abort if suspicious secret patterns are detected.
- Abort push when current branch has no upstream tracking branch.
- Never guess remote/upstream automatically.

## Example
```bash
./scripts/safe-commit-push.sh
```

## Acceptance Criteria
- Clean abort with clear reason when no changes, no upstream, or sensitive matches are found.
- On success, output includes commit SHA, branch, and upstream target.
