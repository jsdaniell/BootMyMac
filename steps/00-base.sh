# shellcheck shell=bash
# Shared helpers + the always-on steps: preflight, homebrew, core, questions.

load_brew_env() {
  if [ -x /opt/homebrew/bin/brew ]; then eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -x /usr/local/bin/brew ]; then eval "$(/usr/local/bin/brew shellenv)"; fi
}

# brew_formula <formula>  — installs if missing
brew_formula() {
  local f=$1
  if brew list --formula "$f" >/dev/null 2>&1; then
    log "formula already installed: $f"; return 0
  fi
  run "brew install $f" brew install "$f"
}

# brew_cask <cask> [App name in /Applications]  — installs if missing
brew_cask() {
  local c=$1 app=${2:-}
  if brew list --cask "$c" >/dev/null 2>&1; then
    log "cask already installed: $c"; return 0
  fi
  if [ -n "$app" ] && { [ -d "/Applications/$app.app" ] || [ -d "$HOME/Applications/$app.app" ]; }; then
    log "app already present: $app"; return 0
  fi
  run "brew install --cask $c" brew install --cask "$c"
}

# install_file <src> <dest>  — copies, keeping a timestamped backup when different
install_file() {
  local src=$1 dest=$2
  if [ -f "$dest" ] && cmp -s "$src" "$dest"; then return 0; fi
  if [ -n "${DRY_RUN:-}" ]; then info "(dry-run) would write $dest"; return 0; fi
  if [ -f "$dest" ]; then
    local bak="$dest.bootmymac-backup-$(date +%Y%m%d-%H%M%S)"
    cp -p "$dest" "$bak" && info "Backed up $(basename "$dest") → $bak"
  fi
  mkdir -p "$(dirname "$dest")"
  cp "$src" "$dest"
}

keep_sudo_alive() {
  ( while true; do sudo -n true 2>/dev/null; sleep 45; kill -0 "$$" 2>/dev/null || exit; done ) &
  SUDO_KEEPALIVE_PID=$!
  trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null' EXIT
}

# ── preflight ────────────────────────────────────────────────────────────────
step_preflight() {
  info "macOS $(sw_vers -productVersion) on $(uname -m) — user $(whoami)"
  if [ "$(id -u)" -eq 0 ]; then err "Do not run this script with sudo; it asks for your password itself."; return 1; fi

  if [ -z "${DRY_RUN:-}" ]; then
    info "Your password is needed once for installers (it is kept alive while the script runs)."
    sudo -v </dev/tty || { err "sudo is required"; return 1; }
    keep_sudo_alive
    # Keep the Mac awake while this runs.
    caffeinate -dimsu -w $$ >/dev/null 2>&1 &
  fi

  if xcode-select -p >/dev/null 2>&1; then
    ok "Command Line Tools already installed ($(xcode-select -p))"
    return 0
  fi
  [ -n "${DRY_RUN:-}" ] && { info "(dry-run) would install Command Line Tools"; return 0; }

  # Headless install, same trick Homebrew uses.
  local flag=/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  touch "$flag"
  local label
  label=$(softwareupdate -l 2>/dev/null | grep -E '^\s*\* Label: Command Line Tools' | sed 's/^.*Label: //' | sort -V | tail -n1)
  if [ -n "$label" ]; then
    run "Installing $label (takes a few minutes)" sudo softwareupdate -i "$label" --agree-to-license
  fi
  rm -f "$flag"

  if ! xcode-select -p >/dev/null 2>&1; then
    warn "Falling back to the Command Line Tools installer window — click Install there."
    xcode-select --install >/dev/null 2>&1
    until xcode-select -p >/dev/null 2>&1; do sleep 10; done
  fi
  ok "Command Line Tools installed"
}

# ── homebrew ─────────────────────────────────────────────────────────────────
step_homebrew() {
  load_brew_env
  if have brew; then
    ok "Homebrew already installed ($(brew --version | head -1))"
    run "brew update" brew update
    record_skip "Homebrew (already installed)"
    return 0
  fi
  [ -n "${DRY_RUN:-}" ] && { info "(dry-run) would install Homebrew"; return 0; }
  run_fg "Installing Homebrew" env NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" </dev/null
  load_brew_env
  have brew || { err "Homebrew installation failed"; return 1; }
  record_ok "Homebrew"
}

# ── core CLI tools ───────────────────────────────────────────────────────────
step_core() {
  local rc=0 f
  for f in git git-lfs gh gum jq mas; do brew_formula "$f" || rc=1; done
  hash -r
  [ $rc -eq 0 ] && record_ok "Core tools: git, git-lfs, gh, gum, jq, mas"
  return $rc
}

# ── questions (asked up front so the rest can run unattended) ───────────────
step_questions() {
  info "Pick what to install. Everything is selected by default."
  local labels=() s id
  for s in "${ALL_STEPS[@]}"; do
    id=${s%%|*}
    case " $REQUIRED_STEPS " in *" $id "*) continue ;; esac
    labels+=("${s#*|}")
  done
  local picked
  picked=$(choose_many "Components to install" "*" "${labels[@]}")
  SELECTED=" $REQUIRED_STEPS "
  for s in "${ALL_STEPS[@]}"; do
    case "$picked" in *"${s#*|}"*) SELECTED="$SELECTED${s%%|*} " ;; esac
  done
  log "selected steps:$SELECTED"

  step_selected github    && q_git_identity
  step_selected node      && q_node
  step_selected worktrees && q_worktrees
  step_selected apps      && q_apps
  step_selected android   && q_android
  step_selected xcode     && q_xcode
  q_extra_formulae
  ok "Got it — the remaining steps run mostly unattended (GitHub login and repo picking still need you)."
}

EXTRA_FORMULAE_PICKED=""
EXTRA_FORMULAE_ASKED=""
q_extra_formulae() {
  local items=() pre="" e name
  for e in "${EXTRA_FORMULAE[@]}"; do
    name=${e%%|*}; items+=("$name")
    [ "${e##*|}" = 1 ] && pre="$pre${pre:+,}$name"
  done
  EXTRA_FORMULAE_PICKED=$(choose_many "Extra CLI tools (Homebrew)" "$pre" "${items[@]}")
  EXTRA_FORMULAE_ASKED=1
  local f
  for f in $EXTRA_FORMULAE_PICKED; do brew_formula "$f" || record_fail "brew $f"; done
}
