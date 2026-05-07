#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[safe-commit-push] %s\n' "$*"
}

fail() {
  printf '[safe-commit-push] ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

is_git_repo() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1
}

has_changes() {
  [[ -n "$(git status --porcelain)" ]]
}

repo_root() {
  git rev-parse --show-toplevel
}

maybe_update_gitignore_for_artifacts() {
  [[ "${AUTO_UPDATE_GITIGNORE:-1}" == "1" ]] || {
    log 'AUTO_UPDATE_GITIGNORE=0, skipping artifact ignore update'
    return 0
  }

  local root gi added=0
  root="$(repo_root)"
  gi="$root/.gitignore"

  if [[ ! -e "$gi" ]]; then
    : >"$gi" || fail "cannot create .gitignore at $gi"
  fi
  [[ -w "$gi" ]] || fail ".gitignore is not writable: $gi"

  local -a rules
  rules=(
    "*.out"
    "*.tmp"
    "*.cache"
    "*.pid"
    "*.seed"
    ".pytest_cache/"
    "coverage/"
  )

  local r
  for r in "${rules[@]}"; do
    if ! grep -Fxq -- "$r" "$gi"; then
      printf '%s\n' "$r" >>"$gi"
      added=$((added + 1))
    fi
  done

  if [[ "$added" -gt 0 ]]; then
    log "added $added artifact ignore rule(s) to .gitignore"
  else
    log 'artifact ignore rules already present in .gitignore'
  fi
}

stage_all() {
  log 'staging all changes (git add -A)'
  git add -A
}

scan_staged_paths() {
  local staged
  staged="$(git diff --cached --name-only)"
  [[ -z "$staged" ]] && return 0

  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    case "$f" in
      *.env|*.pem|*.p12|*id_rsa*|*.key)
        fail "sensitive file pattern detected in staged path: $f"
        ;;
    esac
  done <<< "$staged"
}

scan_staged_diff() {
  local diff
  diff="$(git diff --cached -U0 --no-color)"
  [[ -z "$diff" ]] && return 0

  # Allow config assignments that clearly use env placeholders instead of literals.
  local placeholder_assignment
  placeholder_assignment='(token|password|secret)[[:space:]]*[:=][[:space:]]*"?\$\{[A-Za-z_][A-Za-z0-9_]*\}"?'

  local -a patterns
  patterns=(
    'BEGIN [A-Z0-9 ]*PRIVATE KEY'
    'AKIA[0-9A-Z]{16}'
    '(token|password|secret)[[:space:]]*[:=][[:space:]]*[^[:space:]]+'
    'xox[baprs]-[0-9A-Za-z-]+'
    'ghp_[0-9A-Za-z]{36}'
  )

  if [[ "${SAFE_SCAN_STRICT:-0}" == "1" ]]; then
    patterns+=(
      '[A-Za-z0-9_\-]{20,}\.[A-Za-z0-9_\-]{20,}\.[A-Za-z0-9_\-]{20,}'
      'AIza[0-9A-Za-z\-_]{35}'
    )
  fi

  local matched=0
  local p filtered
  for p in "${patterns[@]}"; do
    if grep -nE -- "$p" <<< "$diff" >/tmp/safe_commit_push_match.out; then
      filtered="$(grep -nEv -- "$placeholder_assignment" /tmp/safe_commit_push_match.out || true)"
      if [[ -n "$filtered" ]]; then
        matched=1
        log "sensitive pattern matched: $p"
        sed -n '1,10p' <<< "$filtered" >&2
      fi
    fi
  done

  rm -f /tmp/safe_commit_push_match.out

  [[ "$matched" -eq 0 ]] || fail 'sensitive content detected in staged diff; commit blocked'
}

build_commit_message() {
  local ns added modified deleted prefix
  ns="$(git diff --cached --name-status)"
  prefix="${FALLBACK_COMMIT_PREFIX:-chore: update}"

  local total=0
  added=0
  modified=0
  deleted=0

  while IFS=$'\t' read -r status _rest; do
    [[ -z "$status" ]] && continue
    total=$((total + 1))
    case "$status" in
      A*) added=$((added + 1)) ;;
      M*) modified=$((modified + 1)) ;;
      D*) deleted=$((deleted + 1)) ;;
      R*|C*) modified=$((modified + 1)) ;;
      *) modified=$((modified + 1)) ;;
    esac
  done <<< "$ns"

  [[ "$total" -gt 0 ]] || fail 'no staged changes found after staging'

  local kinds=()
  [[ "$added" -gt 0 ]] && kinds+=("+${added} added")
  [[ "$modified" -gt 0 ]] && kinds+=("~${modified} modified")
  [[ "$deleted" -gt 0 ]] && kinds+=("-${deleted} deleted")

  local summary='changes'
  if [[ "${#kinds[@]}" -gt 0 ]]; then
    summary="$(IFS=', '; echo "${kinds[*]}")"
  fi

  printf '%s %d files (%s)' "$prefix" "$total" "$summary"
}

commit_changes() {
  local msg
  msg="$(build_commit_message)"
  log "generated commit message: $msg"

  if ! git commit -m "$msg"; then
    fail 'git commit failed'
  fi
}

push_upstream() {
  local branch upstream
  branch="$(git rev-parse --abbrev-ref HEAD)"
  [[ -n "$branch" && "$branch" != 'HEAD' ]] || fail 'detached HEAD is not supported for auto-push'

  upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
  [[ -n "$upstream" ]] || fail "no upstream tracking branch for '$branch'; run: git push -u origin $branch"

  log "pushing branch '$branch' to upstream '$upstream'"
  git push

  local sha
  sha="$(git rev-parse --short HEAD)"
  log "success: commit $sha pushed to $upstream"
}

main() {
  require_cmd git

  is_git_repo || fail 'current directory is not a git repository'
  has_changes || fail 'no uncommitted changes'

  log 'preflight checks passed'

  maybe_update_gitignore_for_artifacts
  stage_all
  scan_staged_paths
  scan_staged_diff
  commit_changes
  push_upstream
}

main "$@"
