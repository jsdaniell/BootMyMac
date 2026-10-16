#!/bin/bash
# Renames worktrees whose branch was merged to merged_<name> — managed by BootMyMac.
# Runs hourly via launchd (com.bootmymac.worktree-sweep) and on demand with `wtsweep`.
#
# A worktree counts as merged when either:
#   • GitHub has a merged pull request for its branch (covers squash/rebase merges), or
#   • its branch was pushed, the remote branch is gone, and all its commits are on
#     the default branch (a regular merge with "delete branch" on).
# Worktrees that a running process (a Claude session, a terminal) is sitting in are
# left alone and retried on the next run.

set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$HOME/.local/bin:$PATH"
export GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=never

WORKTREES_ROOT="$HOME/worktrees"
[ -f "$HOME/.claude/worktrees.conf" ] && . "$HOME/.claude/worktrees.conf"
[ -d "$WORKTREES_ROOT" ] || exit 0

with_timeout() { local s=$1; shift; perl -e 'alarm shift; exec @ARGV' "$s" "$@"; }
say() { echo "[$(date '+%F %T')] $*"; }

BUSY=$(lsof -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')

for dir in "$WORKTREES_ROOT"/*/*/; do
  [ -d "$dir" ] || continue
  dir=${dir%/}
  name=$(basename "$dir")
  case "$name" in merged_*) continue ;; esac
  git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 || continue
  branch=$(git -C "$dir" symbolic-ref --quiet --short HEAD 2>/dev/null) || continue

  merged=0
  if command -v gh >/dev/null 2>&1 && git -C "$dir" remote get-url origin 2>/dev/null | grep -q 'github.com'; then
    n=$(cd "$dir" && with_timeout 30 gh pr list --head "$branch" --state merged --json number --jq 'length' 2>/dev/null)
    [ "${n:-0}" -gt 0 ] 2>/dev/null && merged=1
  fi

  if [ $merged -eq 0 ]; then
    # Read the upstream from config: `@{u}` stops resolving once the remote branch is pruned.
    up_remote=$(git -C "$dir" config "branch.$branch.remote" 2>/dev/null)
    up_merge=$(git -C "$dir" config "branch.$branch.merge" 2>/dev/null)
    if [ "$up_remote" = origin ] && [ -n "$up_merge" ]; then
      upstream="origin/${up_merge#refs/heads/}"
      with_timeout 30 git -C "$dir" fetch --quiet --prune origin >/dev/null 2>&1
      default=$(git -C "$dir" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)
      if [ -n "$default" ] && ! git -C "$dir" show-ref --verify --quiet "refs/remotes/$upstream" \
         && [ -z "$(git -C "$dir" rev-list "$default..HEAD" 2>/dev/null)" ]; then
        merged=1
      fi
    fi
  fi

  [ $merged -eq 1 ] || continue

  if printf '%s\n' "$BUSY" | grep -q -e "^$dir\$" -e "^$dir/"; then
    say "merged but in use, will retry: $dir"
    continue
  fi

  target="$(dirname "$dir")/merged_$name"
  [ -e "$target" ] && { say "target exists, skipping: $target"; continue; }
  if git -C "$dir" worktree move "$dir" "$target" 2>/dev/null; then
    say "renamed $dir -> $target ($branch merged)"
  else
    say "failed to rename $dir"
  fi
done
