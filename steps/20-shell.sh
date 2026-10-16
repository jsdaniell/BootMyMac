# shellcheck shell=bash
# zsh / Oh My Zsh, nvm + Node, Go, Hyper.

step_zsh() {
  local rc=0 zsh_dir="$HOME/.oh-my-zsh"
  if [ -d "$zsh_dir" ]; then
    ok "Oh My Zsh already installed"
  else
    run "Installing Oh My Zsh" env RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c \
      "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended || rc=1
  fi

  local p name url dest
  for p in "${ZSH_PLUGINS[@]}"; do
    name=${p%%|*}; url=${p#*|}
    dest="$zsh_dir/custom/plugins/$name"
    if [ -d "$dest" ]; then ok "zsh plugin $name already installed"; continue; fi
    run "zsh plugin $name" git clone --depth=1 "$url" "$dest" || rc=1
  done

  install_file "$BOOT_DIR/dotfiles/zshrc" "$HOME/.zshrc"
  install_file "$BOOT_DIR/dotfiles/zprofile" "$HOME/.zprofile"

  # zsh is the default shell on modern macOS, but make sure.
  local login_shell
  login_shell=$(dscl . -read "/Users/$(whoami)" UserShell 2>/dev/null | awk '{print $2}')
  case "$login_shell" in */zsh) ;; *)
  if [ -z "${DRY_RUN:-}" ]; then
    run "Set zsh as login shell" sudo chsh -s /bin/zsh "$(whoami)" || rc=1
  fi ;;
  esac

  if [ -z "${DRY_RUN:-}" ]; then
    if zsh -i -c 'type killp >/dev/null && alias onsleep >/dev/null && alias offsleep >/dev/null' </dev/null >/dev/null 2>&1; then
      ok "killp, onsleep and offsleep are available in zsh"
    else
      warn "Could not verify killp/onsleep/offsleep in a zsh session"; rc=1
    fi
  fi
  [ $rc -eq 0 ] && record_ok "Oh My Zsh + plugins + .zshrc (killp, onsleep, offsleep)"
  return $rc
}

NODE_VERSIONS=""; NPM_PICKED=""; NODE_ASKED=""
q_node() {
  [ -n "$NODE_ASKED" ] && return 0
  NODE_VERSIONS=$(ask_input "Node versions to install with nvm (first = default)" "$NODE_VERSIONS_DEFAULT")
  NPM_PICKED=$(choose_many "Global npm packages" "*" "${NPM_GLOBALS[@]}")
  NODE_ASKED=1
}

load_nvm() {
  export NVM_DIR="$HOME/.nvm"
  # shellcheck disable=SC1091
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
}

step_node() {
  q_node
  local rc=0
  load_nvm
  if have nvm; then
    ok "nvm already installed ($(nvm --version))"
  else
    local tag
    tag=$(curl -fsSL https://api.github.com/repos/nvm-sh/nvm/releases/latest 2>/dev/null | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)
    tag=${tag:-v0.40.3}
    run "Installing nvm $tag" env PROFILE=/dev/null bash -c "curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/$tag/install.sh | bash" || return 1
    load_nvm
  fi
  [ -n "${DRY_RUN:-}" ] && { info "(dry-run) would install Node $NODE_VERSIONS"; return 0; }
  have nvm || { err "nvm did not load"; return 1; }

  local v first=""
  for v in $NODE_VERSIONS; do
    [ -z "$first" ] && first=$v
    run "Node $v" nvm install "$v" --no-progress || rc=1
  done
  if [ -n "$first" ]; then
    nvm alias default "$first" >/dev/null && nvm use default >/dev/null
    ok "Default Node: $(node -v)"
  fi

  local pkg
  for pkg in $NPM_PICKED; do
    if npm ls -g --depth=0 "$pkg" >/dev/null 2>&1; then ok "npm $pkg already installed"; continue; fi
    run "npm i -g $pkg" npm install -g "$pkg" || { record_fail "npm $pkg"; }
  done
  [ $rc -eq 0 ] && record_ok "nvm + Node $NODE_VERSIONS (default $first)"
  return $rc
}

step_go() {
  brew_formula go || return 1
  [ -z "${DRY_RUN:-}" ] && mkdir -p "$HOME/go/bin"
  have go && ok "$(go version)"
  record_ok "Go"
}

step_hyper() {
  local rc=0
  brew_cask hyper Hyper || rc=1
  install_file "$BOOT_DIR/dotfiles/hyper.js" "$HOME/.hyper.js"
  if [ -z "${DRY_RUN:-}" ] && [ -d /Applications/Hyper.app ]; then
    # Hyper installs the plugins listed in ~/.hyper.js (hyperocean) on launch.
    open -g -a Hyper && ok "Hyper launched in the background to install its plugins"
  fi
  [ $rc -eq 0 ] && record_ok "Hyper + ~/.hyper.js (plugins: hyperocean)"
  return $rc
}
