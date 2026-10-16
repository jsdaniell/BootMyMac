# shellcheck shell=bash
# Claude Code CLI, Claude Desktop, and central worktrees for Claude Code.

step_claude() {
  local rc=0
  export PATH="$HOME/.local/bin:$PATH"
  if have claude; then
    ok "Claude Code CLI already installed ($(claude --version 2>/dev/null | head -1)) — it auto-updates itself"
  else
    # Native installer: always the latest version, auto-updates, installs to ~/.local/bin/claude
    run "Installing Claude Code CLI (latest)" bash -c "curl -fsSL https://claude.ai/install.sh | bash" || rc=1
    hash -r
    [ -z "${DRY_RUN:-}" ] && { have claude && ok "claude $(claude --version 2>/dev/null | head -1)" || rc=1; }
  fi

  brew_cask claude Claude || rc=1   # Claude Desktop (separate app from the CLI)

  local settings="$HOME/.claude/settings.json"
  if [ ! -f "$settings" ]; then
    install_file "$BOOT_DIR/dotfiles/claude-settings.json" "$settings"
    ok "Restored ~/.claude/settings.json"
  else
    ok "~/.claude/settings.json already exists (kept)"
  fi
  [ $rc -eq 0 ] && record_ok "Claude Code CLI + Claude Desktop (log in on first launch: run 'claude')"
  return $rc
}

WORKTREES_ROOT=""
q_worktrees() {
  [ -n "$WORKTREES_ROOT" ] && return 0
  local cur=""
  [ -f "$HOME/.claude/worktrees.conf" ] && cur=$(. "$HOME/.claude/worktrees.conf"; echo "${WORKTREES_ROOT:-}")
  WORKTREES_ROOT=$(ask_input "Central folder for ALL Claude Code worktrees" "${cur:-$WORKTREES_ROOT_DEFAULT}")
  WORKTREES_ROOT=${WORKTREES_ROOT/#\~/$HOME}
}

step_worktrees() {
  q_worktrees
  local hooks="$HOME/.claude/hooks" settings="$HOME/.claude/settings.json"
  local label="com.bootmymac.worktree-sweep"
  local plist="$HOME/Library/LaunchAgents/$label.plist"

  if [ -n "${DRY_RUN:-}" ]; then
    info "(dry-run) would install hooks into $hooks, set WORKTREES_ROOT=$WORKTREES_ROOT, register hooks in $settings and load $label"
    return 0
  fi

  mkdir -p "$hooks" "$WORKTREES_ROOT" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
  local f
  for f in worktree-create.sh worktree-remove.sh worktree-sweep-merged.sh; do
    cp "$BOOT_DIR/claude/hooks/$f" "$hooks/$f" && chmod +x "$hooks/$f"
  done
  cat >"$HOME/.claude/worktrees.conf" <<EOF
# Read by ~/.claude/hooks/worktree-*.sh (managed by BootMyMac)
WORKTREES_ROOT="$WORKTREES_ROOT"
# fresh = branch new worktrees from origin's default branch; head = from your current HEAD
WORKTREE_BASE="fresh"
EOF

  # Register the hooks in the global settings, keeping everything else.
  [ -f "$settings" ] || echo '{}' >"$settings"
  local tmp; tmp=$(mktemp)
  if jq --arg c "$hooks/worktree-create.sh" --arg r "$hooks/worktree-remove.sh" '
      .hooks = (.hooks // {})
      | .hooks.WorktreeCreate = [{"hooks":[{"type":"command","command":$c}]}]
      | .hooks.WorktreeRemove = [{"hooks":[{"type":"command","command":$r}]}]
    ' "$settings" >"$tmp"; then
    cp "$settings" "$settings.bootmymac-backup-$(date +%Y%m%d-%H%M%S)"
    mv "$tmp" "$settings"
    ok "WorktreeCreate/WorktreeRemove hooks registered in ~/.claude/settings.json"
  else
    rm -f "$tmp"; err "Could not update $settings (invalid JSON?)"; return 1
  fi

  # Hourly sweeper: renames merged worktrees to merged_<name>.
  cat >"$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key>
  <array><string>/bin/bash</string><string>$hooks/worktree-sweep-merged.sh</string></array>
  <key>StartInterval</key><integer>3600</integer>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$HOME/Library/Logs/worktree-sweep.log</string>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/worktree-sweep.log</string>
</dict>
</plist>
EOF
  launchctl bootout "gui/$(id -u)/$label" >/dev/null 2>&1
  if launchctl bootstrap "gui/$(id -u)" "$plist" 2>>"$LOG_FILE"; then
    ok "Merged-worktree sweeper scheduled hourly ($label)"
  else
    warn "Could not load $label; run it manually with: wtsweep"
  fi

  record_ok "Claude Code worktrees → $WORKTREES_ROOT/<repo>/<name> (merged ones renamed merged_<name> hourly)"
}
