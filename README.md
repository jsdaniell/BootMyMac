# BootMyMac

An interactive script that sets up a freshly formatted Mac with my tools, shell, apps and repositories.

## Run it on a fresh Mac

Open **Terminal** and paste:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/jsdaniell/BootMyMac/main/install.sh)"
```

You don't need git first. The installer downloads this repo to `~/.bootmymac/src` and runs `boot.sh`.

Already have the repo cloned?

```bash
./boot.sh            # interactive (recommended)
./boot.sh --list     # list the steps
./boot.sh --only zsh,claude,worktrees   # run some steps only
./boot.sh --dry-run  # show what would happen, change nothing
./boot.sh --yes      # accept every default
```

You can **re-run it anytime**. Every step checks what's already there and skips it, so after a failure you just run it again.

## What it does (in order)

| # | Step | Notes |
|---|------|-------|
| 1 | Preflight | Asks for your password once (kept alive), keeps the Mac awake, installs Xcode Command Line Tools |
| 2 | Homebrew | |
| 3 | Core CLI tools | git, git-lfs, gh, gum (the interactive UI), jq, mas |
| 4 | **Questions** | Choose components, Node versions, npm globals, worktree folder, apps, Android, Xcode. The remaining steps then run mostly unattended |
| 5 | Git + GitHub | `~/.gitconfig` (name, email, aliases), **Git Credential Manager** set as the credential helper, `gh auth login` in the browser, and your GitHub account added to GCM (by reusing the gh login, or a second browser login as fallback) |
| 6 | Repositories | Pick organizations, then repos in each (type to search). They're cloned to `~/Documents/Development/<Org>/<repo>` |
| 7 | Zsh | Oh My Zsh, `robbyrussell`, plugins (autosuggestions, syntax-highlighting, fast-syntax-highlighting), `.zshrc` with **`killp`**, **`onsleep`**, **`offsleep`** |
| 8 | Node | nvm (latest release), Node 22 (default) + 20, global npm packages |
| 9 | Go | via Homebrew |
| 10 | Hyper | App + `~/.hyper.js` (plugin `hyperocean`, which Hyper installs on first launch) |
| 11 | Claude | **Claude Code CLI** (native installer, always latest, auto-updates) and **Claude Desktop** (a separate app). Restores `~/.claude/settings.json` |
| 12 | Worktrees | All Claude Code worktrees go in one central folder (see below) |
| 13 | Apps | ClickUp, Structured, MongoDB Compass, WhatsApp, Notion, WebStorm, GoLand, Arc, Slack (+ optional Docker, Postman, Figma, Chrome, Linear, VS Code) |
| 14 | Android | Android Studio, JDK 17, SDK. It shows the API levels that are actually available so you can pick; an emulator is optional |
| 15 | Xcode | From the App Store via `mas`. Accepts the license, runs first launch, and can download the iOS Simulator |

At the end you get a **summary** of what was done, what was skipped, what failed, and what you **must do manually** (with links).

### Things that stay manual (the summary reminds you)

- **Preply**: it's an iPhone/iPad app from the App Store, which the CLI can't install.
- **App Store apps** (Structured, Xcode): `mas` installs them only when you're signed in to the App Store. If that fails, the script opens the App Store page and lists the app in the summary. After installing Xcode, run `./boot.sh --only xcode` to finish its setup.
- **Logging in to apps**: Claude (run `claude`), Slack, Notion and so on.

## Claude Code worktrees in one central folder

Claude Code has no setting for where worktrees go, so this uses hooks in `~/.claude/settings.json`. They apply to every project:

- **`WorktreeCreate`** → `~/.claude/hooks/worktree-create.sh` creates `<WORKTREES_ROOT>/<repo>/<name>` on branch `worktree-<name>`. By default it branches from `origin`'s default branch, just like Claude's own behavior. It also handles resuming, `--worktree "#123"` (PRs), and copies files listed in `.worktreeinclude` (such as `.env`).
- **`WorktreeRemove`** → `~/.claude/hooks/worktree-remove.sh` removes the worktree and its `worktree-*` branch. It refuses to delete anything outside `WORKTREES_ROOT`.
- **Merged → `merged_<name>`**: `~/.claude/hooks/worktree-sweep-merged.sh` runs **every hour** (launchd agent `com.bootmymac.worktree-sweep`). It renames a worktree once its branch is merged. A merge is detected either from a merged GitHub PR (this covers squash merges) or from the branch being pushed, then deleted on the remote, with all its commits on the default branch. Worktrees in use by a running process are skipped until the next run. To run it right away: `wtsweep`. Log: `~/Library/Logs/worktree-sweep.log`.

Config is in `~/.claude/worktrees.conf`:

```bash
WORKTREES_ROOT="$HOME/worktrees"
WORKTREE_BASE="fresh"   # or "head" to branch from your current HEAD
```

## Customizing

- `config.sh` holds the git identity, Node versions, npm globals, zsh plugins, extra brew formulae, and the apps list (`cask`, `mas` or `manual`).
- `dotfiles/` holds `zshrc`, `zprofile`, `hyper.js`, `gitconfig`, and `claude-settings.json`. When the script replaces one of your existing files, it first saves a copy as `*.bootmymac-backup-<timestamp>`.
- Put machine-specific shell config in `~/.zshrc.local`. It's sourced automatically.

Logs are written to `~/.bootmymac/boot-<timestamp>.log`.
