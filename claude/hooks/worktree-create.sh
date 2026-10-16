#!/bin/bash
# Claude Code WorktreeCreate hook — managed by BootMyMac.
#
# Creates every worktree in one central folder:
#   $WORKTREES_ROOT/<repo>/<name>   on branch  worktree-<name>
# and prints ONLY the worktree path on stdout (Claude Code reads the last line).
# Everything else goes to stderr.
#
# Config: ~/.claude/worktrees.conf
#   WORKTREES_ROOT="$HOME/worktrees"
#   WORKTREE_BASE="fresh"   # fresh = branch from origin's default branch, head = from current HEAD

set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
export GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=never

WORKTREES_ROOT="$HOME/worktrees"
WORKTREE_BASE="fresh"
[ -f "$HOME/.claude/worktrees.conf" ] && . "$HOME/.claude/worktrees.conf"

die() { echo "worktree-create: $*" >&2; exit 1; }
json_get() { printf '%s' "$INPUT" | plutil -extract "$1" raw -o - - 2>/dev/null; }
# Run a command with a timeout (macOS has no `timeout`).
with_timeout() { local s=$1; shift; perl -e 'alarm shift; exec @ARGV' "$s" "$@"; }

INPUT=$(cat)
NAME=$(json_get name)
CWD=$(json_get cwd)
[ -n "$NAME" ] || die "no worktree name in hook input"
[ -n "$CWD" ] || CWD=$PWD
case "$NAME" in */*|*..*) NAME=$(printf '%s' "$NAME" | tr '/' '-' | sed 's/\.\././g') ;; esac

cd "$CWD" 2>/dev/null || die "cannot cd into $CWD"
COMMON=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || die "$CWD is not inside a git repository"
case "$COMMON" in
  */.git) MAIN_ROOT=$(dirname "$COMMON") ;;
  *) MAIN_ROOT=$COMMON ;;  # bare repository
esac
REPO=$(basename "$MAIN_ROOT"); REPO=${REPO%.git}

mkdir -p "$WORKTREES_ROOT/$REPO" || die "cannot create $WORKTREES_ROOT/$REPO"
# Resolve symlinks so Claude Code accepts the path.
ROOT_REAL=$(cd "$WORKTREES_ROOT/$REPO" && pwd -P)
DEST="$ROOT_REAL/$NAME"

# Resume: worktree already exists (e.g. `claude --worktree <name> --resume`).
if [ -d "$DEST" ] && git -C "$DEST" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Reusing existing worktree $DEST" >&2
  echo "$DEST"
  exit 0
fi
[ -e "$DEST" ] && die "$DEST exists and is not a git worktree"

g() { git -C "$MAIN_ROOT" "$@"; }

BRANCH="worktree-$NAME"
BASE=""

# `claude --worktree "#123"` → name pr-123: branch from the pull request head.
if [[ "$NAME" =~ ^pr-([0-9]+)$ ]]; then
  PR=${BASH_REMATCH[1]}
  if with_timeout 30 git -C "$MAIN_ROOT" fetch --quiet origin "pull/$PR/head" >&2 2>&1; then
    BASE=$(g rev-parse FETCH_HEAD)
    BRANCH="pr-$PR"
  fi
fi

if [ -z "$BASE" ] && [ "$WORKTREE_BASE" = "fresh" ] && g remote get-url origin >/dev/null 2>&1; then
  DEFAULT=$(g symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)
  if [ -z "$DEFAULT" ]; then
    with_timeout 15 git -C "$MAIN_ROOT" remote set-head origin --auto >/dev/null 2>&1
    DEFAULT=$(g symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)
  fi
  if [ -n "$DEFAULT" ]; then
    with_timeout 15 git -C "$MAIN_ROOT" fetch --quiet origin "${DEFAULT#origin/}" >&2 2>&1 || echo "fetch failed, using cached $DEFAULT" >&2
    BASE=$DEFAULT
  fi
fi
[ -n "$BASE" ] || BASE=$(git rev-parse HEAD 2>/dev/null) || die "repository has no commits"

if g show-ref --verify --quiet "refs/heads/$BRANCH"; then
  if g worktree list --porcelain | grep -qx "branch refs/heads/$BRANCH"; then
    # Branch is busy in another worktree (e.g. an old merged_ one): use a fresh branch.
    BRANCH="$BRANCH-$(date +%Y%m%d%H%M%S)"
    g worktree add --no-track -b "$BRANCH" "$DEST" "$BASE" >&2 || die "git worktree add failed"
  else
    g worktree add "$DEST" "$BRANCH" >&2 || die "git worktree add failed"
  fi
else
  g worktree add --no-track -b "$BRANCH" "$DEST" "$BASE" >&2 || die "git worktree add failed"
fi

# Honour .worktreeinclude (copy gitignored files such as .env into the worktree),
# since a WorktreeCreate hook replaces Claude Code's built-in handling of it.
if [ -f "$MAIN_ROOT/.worktreeinclude" ]; then
  ( cd "$MAIN_ROOT" && git ls-files --others --ignored --exclude-from=.worktreeinclude ) |
  while IFS= read -r f; do
    [ -f "$MAIN_ROOT/$f" ] || continue
    mkdir -p "$DEST/$(dirname "$f")" && cp -p "$MAIN_ROOT/$f" "$DEST/$f"
  done
fi

echo "Created worktree $DEST on branch $BRANCH (base $BASE)" >&2
echo "$DEST"
