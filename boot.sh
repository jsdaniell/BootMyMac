#!/bin/bash
# BootMyMac — sets up a fresh Mac the way I like it.
#
#   ./boot.sh                 interactive run (recommended)
#   ./boot.sh --only zsh,go   run only some steps (see --list)
#   ./boot.sh --yes           accept every default without asking
#   ./boot.sh --dry-run       show what would run, change nothing
#
# Safe to re-run: every step checks what is already installed and skips it.

BOOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
STATE_DIR="$HOME/.bootmymac"
mkdir -p "$STATE_DIR"
LOG_FILE="$STATE_DIR/boot-$(date +%Y%m%d-%H%M%S).log"
: >"$LOG_FILE"

# shellcheck source=lib/ui.sh
. "$BOOT_DIR/lib/ui.sh"
# shellcheck source=config.sh
. "$BOOT_DIR/config.sh"
for f in "$BOOT_DIR"/steps/*.sh; do . "$f"; done

# id|label   (order = execution order)
ALL_STEPS=(
  "preflight|Preflight checks & Command Line Tools"
  "homebrew|Homebrew"
  "core|Core CLI tools (git, gh, gum, jq…)"
  "questions|What do you want to install?"
  "github|Git + GitHub login (Git Credential Manager)"
  "repos|Clone GitHub repositories"
  "zsh|Oh My Zsh, plugins & .zshrc (killp, onsleep, offsleep)"
  "node|nvm + Node.js"
  "go|Go"
  "hyper|Hyper terminal + config/plugins"
  "claude|Claude Code CLI + Claude Desktop"
  "worktrees|Claude Code central worktrees (hooks + merged_ sweeper)"
  "apps|Desktop apps"
  "android|Android Studio + SDK"
  "xcode|Xcode + command line tools"
)
# Steps that always run (the others can be unticked in "questions").
REQUIRED_STEPS="preflight homebrew core questions"

ONLY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --only) ONLY=$(printf '%s' "$2" | tr ',' ' '); shift 2 ;;
    --only=*) ONLY=$(printf '%s' "${1#--only=}" | tr ',' ' '); shift ;;
    --yes|-y) export BOOT_ASSUME_DEFAULTS=1; shift ;;
    --dry-run|-n) export DRY_RUN=1; shift ;;
    --no-gum) export BOOT_NO_GUM=1; shift ;;
    --list)
      for s in "${ALL_STEPS[@]}"; do printf '  %-11s %s\n' "${s%%|*}" "${s#*|}"; done
      exit 0 ;;
    -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) err "Unknown option: $1"; exit 1 ;;
  esac
done

# SELECTED holds the step ids that will run (space separated, padded).
if [ -n "$ONLY" ]; then
  # Always make sure brew & core tools are usable, even with --only.
  SELECTED=" preflight homebrew core $ONLY "
else
  SELECTED=" "
  for s in "${ALL_STEPS[@]}"; do SELECTED="$SELECTED${s%%|*} "; done
fi
step_selected() { case "$SELECTED" in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

[ "$(uname -s)" = Darwin ] || { err "This script is for macOS."; exit 1; }

banner
printf '  Log file: %s\n' "$LOG_FILE"
[ -n "${DRY_RUN:-}" ] && warn "DRY RUN — nothing will be changed."

TOTAL=${#ALL_STEPS[@]}
idx=0
for s in "${ALL_STEPS[@]}"; do
  idx=$((idx + 1))
  id=${s%%|*}; label=${s#*|}
  if ! step_selected "$id"; then
    case " $REQUIRED_STEPS " in *" $id "*) ;; *) log "not selected: $id"; continue ;; esac
    [ -n "$ONLY" ] && [ "$id" = questions ] && continue
  fi
  progress_bar "$idx" "$TOTAL" "$label"
  "step_$id"
  rc=$?
  if [ $rc -ne 0 ]; then
    record_fail "$label"
    if [ "$id" = homebrew ] || [ "$id" = preflight ]; then
      err "Cannot continue without this step."
      print_summary
      exit 1
    fi
  fi
done

progress_bar "$TOTAL" "$TOTAL" "All done"
print_summary
if [ ${#SUMMARY_MANUAL[@]} -gt 0 ] || [ ${#SUMMARY_FAIL[@]} -gt 0 ]; then
  cp "$LOG_FILE" "$STATE_DIR/last.log" 2>/dev/null
fi
info "Open a new terminal (or run: exec zsh -l) to load the new shell config."
