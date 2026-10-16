#!/bin/bash
# Claude Code WorktreeRemove hook — managed by BootMyMac.
# Removes a worktree created by worktree-create.sh (also when the sweeper already
# renamed it to merged_<name>) and deletes the branch the create hook made.

set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

WORKTREES_ROOT="$HOME/worktrees"
[ -f "$HOME/.claude/worktrees.conf" ] && . "$HOME/.claude/worktrees.conf"
ROOT_REAL=$(cd "$WORKTREES_ROOT" 2>/dev/null && pwd -P) || ROOT_REAL=$WORKTREES_ROOT

INPUT=$(cat)
WT=$(printf '%s' "$INPUT" | plutil -extract worktree_path raw -o - - 2>/dev/null)
[ -n "$WT" ] || { echo "worktree-remove: no worktree_path" >&2; exit 1; }

if [ ! -d "$WT" ]; then
  ALT="$(dirname "$WT")/merged_$(basename "$WT")"
  if [ -d "$ALT" ]; then WT=$ALT; else exit 0; fi   # already gone
fi
WT=$(cd "$WT" && pwd -P)

# Safety: never delete anything outside the central worktrees folder.
case "$WT" in
  "$ROOT_REAL"/*) ;;
  *) echo "worktree-remove: refusing to delete $WT (outside $ROOT_REAL)" >&2; exit 1 ;;
esac

COMMON=$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
if [ -z "$COMMON" ]; then
  rm -rf "$WT"
  exit 0
fi
case "$COMMON" in */.git) MAIN_ROOT=$(dirname "$COMMON") ;; *) MAIN_ROOT=$COMMON ;; esac
BRANCH=$(git -C "$WT" symbolic-ref --quiet --short HEAD 2>/dev/null)

git -C "$MAIN_ROOT" worktree remove --force "$WT" >&2 2>&1 || rm -rf "$WT"
git -C "$MAIN_ROOT" worktree prune >&2 2>&1

case "$BRANCH" in
  worktree-*|pr-*) git -C "$MAIN_ROOT" branch -D "$BRANCH" >&2 2>&1 ;;
esac

rmdir "$(dirname "$WT")" 2>/dev/null   # drop the empty <repo> folder
[ ! -d "$WT" ]
