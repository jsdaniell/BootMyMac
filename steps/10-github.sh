# shellcheck shell=bash
# Git config, Git Credential Manager, GitHub login and repository cloning.

GIT_NAME=""; GIT_EMAIL=""
q_git_identity() {
  [ -n "$GIT_NAME" ] && return 0
  GIT_NAME=$(ask_input "Git user.name" "$(git config --global user.name 2>/dev/null || echo "$GIT_NAME_DEFAULT")")
  GIT_EMAIL=$(ask_input "Git user.email" "$(git config --global user.email 2>/dev/null || echo "$GIT_EMAIL_DEFAULT")")
}

gcm_bin() {
  if have git-credential-manager; then command -v git-credential-manager
  elif [ -x /usr/local/share/gcm-core/git-credential-manager ]; then echo /usr/local/share/gcm-core/git-credential-manager
  fi
}

# Does GCM already hold a GitHub credential?
gcm_has_github_account() {
  local gcm; gcm=$(gcm_bin)
  [ -n "$gcm" ] && [ -n "$("$gcm" github list 2>/dev/null)" ]
}

step_github() {
  q_git_identity
  local rc=0

  # 1) ~/.gitconfig base + identity
  if [ ! -f "$HOME/.gitconfig" ]; then
    install_file "$BOOT_DIR/dotfiles/gitconfig" "$HOME/.gitconfig"
  else
    # Merge the base settings into an existing file.
    if [ -z "${DRY_RUN:-}" ]; then
      git config --global alias.commit-all '!f() { git add -A && git commit -m "$1"; }; f'
      git config --global http.postBuffer 157286400
      git config --global url."https://github.com/".insteadOf git@github.com:
    fi
  fi
  if [ -z "${DRY_RUN:-}" ]; then
    git config --global user.name "$GIT_NAME"
    git config --global user.email "$GIT_EMAIL"
  fi
  run "git lfs install" git lfs install --skip-repo || rc=1

  # 2) Git Credential Manager
  brew_cask git-credential-manager || rc=1
  hash -r
  local gcm; gcm=$(gcm_bin)
  if [ -z "$gcm" ] && [ -z "${DRY_RUN:-}" ]; then err "git-credential-manager not found"; return 1; fi
  run "Configure Git Credential Manager as git's credential helper" "${gcm:-git-credential-manager}" configure || rc=1

  # 3) GitHub CLI login (used for the repo picker and the worktree sweeper)
  if gh auth status -h github.com >/dev/null 2>&1; then
    ok "GitHub CLI already logged in as $(gh api user --jq .login 2>/dev/null)"
  else
    info "Logging in to GitHub CLI. Choose 'Login with a web browser' if asked; copy the code shown and paste it in the browser."
    run_fg "gh auth login" gh auth login --hostname github.com --git-protocol https --web --scopes "read:org,repo,workflow" </dev/tty || rc=1
  fi
  # gh may register itself as the github.com credential helper; GCM is the one we want.
  if [ -z "${DRY_RUN:-}" ]; then
    git config --global --unset-all 'credential.https://github.com.helper' 2>/dev/null
    git config --global --unset-all 'credential.https://gist.github.com.helper' 2>/dev/null
    git config --global --remove-section 'credential.https://github.com' 2>/dev/null
    git config --global --remove-section 'credential.https://gist.github.com' 2>/dev/null
  fi

  # 4) Put the GitHub account into GCM so git push/pull/clone just work.
  if gcm_has_github_account; then
    ok "Git Credential Manager already has a GitHub account: $("$gcm" github list | head -1)"
  elif [ -z "${DRY_RUN:-}" ]; then
    local gh_user gh_token
    gh_user=$(gh api user --jq .login 2>/dev/null)
    gh_token=$(gh auth token 2>/dev/null)
    if [ -n "$gh_token" ] && ask_yn "Reuse the GitHub CLI login for Git Credential Manager (no second browser login)?" y; then
      run "GCM: add GitHub account $gh_user" "$gcm" github login --username "$gh_user" --pat "$gh_token" --no-ui || true
    fi
    if ! gcm_has_github_account; then
      info "Opening the browser to log Git Credential Manager in to GitHub…"
      run_fg "GCM: GitHub browser login" "$gcm" github login --browser </dev/tty || rc=1
    fi
  fi

  if [ -z "${DRY_RUN:-}" ]; then
    if gcm_has_github_account; then
      ok "git is authenticated with GitHub via Git Credential Manager ($("$gcm" github list | head -1))"
    else
      err "Git Credential Manager has no GitHub account yet — run: git credential-manager github login"
      rc=1
    fi
  fi

  [ $rc -eq 0 ] && record_ok "Git ($GIT_NAME <$GIT_EMAIL>) + Git Credential Manager + GitHub login"
  return $rc
}

# ── repositories ─────────────────────────────────────────────────────────────
step_repos() {
  if [ -n "${DRY_RUN:-}" ] && ! gh auth status -h github.com >/dev/null 2>&1; then
    info "(dry-run) would list your GitHub orgs/repos and clone the ones you pick into $DEV_DIR/<Org>/<repo>"
    return 0
  fi
  if ! gh auth status -h github.com >/dev/null 2>&1; then
    err "GitHub CLI is not logged in (run the 'github' step first)"; return 1
  fi

  local me owners_raw owners=()
  me=$(gh api user --jq .login)
  owners_raw=$(printf '%s\n' "$me"; gh api user/orgs --paginate --jq '.[].login' 2>/dev/null; \
               gh api user/memberships/orgs --paginate --jq '.[] | select(.state=="active") | .organization.login' 2>/dev/null)
  lines_to_array owners <<<"$(printf '%s\n' "$owners_raw" | awk 'NF && !seen[$0]++')"

  local picked_owners=()
  lines_to_array picked_owners <<<"$(choose_many "GitHub accounts/organizations to clone from" "" "${owners[@]}")"
  if [ ${#picked_owners[@]} -eq 0 ]; then
    info "No organization selected."; record_skip "Repositories (none selected)"; return 0
  fi

  # Collect the selection for every org first, then clone everything.
  local to_clone=() owner repos=() picked=() r
  for owner in "${picked_owners[@]}"; do
    info "Fetching repositories of $owner…"
    lines_to_array repos <<<"$(gh repo list "$owner" --limit 1000 --no-archived --json name --jq '.[].name' 2>/dev/null | sort -f)"
    if [ ${#repos[@]} -eq 0 ]; then warn "No repositories found for $owner"; continue; fi
    lines_to_array picked <<<"$(choose_many "Repositories from $owner → $DEV_DIR/$owner" "" "${repos[@]}")"
    for r in "${picked[@]}"; do to_clone+=("$owner/$r"); done
  done

  if [ ${#to_clone[@]} -eq 0 ]; then record_skip "Repositories (none selected)"; return 0; fi

  local total=${#to_clone[@]} n=0 full dest rc=0 cloned=0
  for full in "${to_clone[@]}"; do
    n=$((n + 1))
    dest="$DEV_DIR/${full%%/*}/${full#*/}"
    if [ -d "$dest/.git" ]; then ok "[$n/$total] $full already cloned"; continue; fi
    mkdir -p "$(dirname "$dest")"
    if run "[$n/$total] Cloning $full" git clone "https://github.com/$full.git" "$dest" \
       || run "[$n/$total] Retrying $full with gh" gh repo clone "$full" "$dest"; then
      cloned=$((cloned + 1))
    else
      record_fail "Clone $full"; rc=1
    fi
  done
  record_ok "Cloned $cloned repositories into $DEV_DIR"
  return $rc
}
