# shellcheck shell=bash
# BootMyMac configuration — edit these lists to change what gets offered.

GIT_NAME_DEFAULT="José Daniel"
GIT_EMAIL_DEFAULT="jose.daniell@outlook.com"
GITHUB_USER_DEFAULT="jsdaniell"

DEV_DIR="$HOME/Documents/Development"      # repos go to $DEV_DIR/<Org>/<repo>
WORKTREES_ROOT_DEFAULT="$HOME/worktrees"   # Claude Code worktrees: <root>/<repo>/<name>

NODE_VERSIONS_DEFAULT="22 20"              # first one becomes the nvm default

# Global npm packages offered (all preselected)
NPM_GLOBALS=(
  yarn
  @openai/codex
  @google/gemini-cli
  commitizen
  eas-cli
  firebase-tools
  vercel
)

ZSH_PLUGINS=(
  "zsh-autosuggestions|https://github.com/zsh-users/zsh-autosuggestions"
  "zsh-syntax-highlighting|https://github.com/zsh-users/zsh-syntax-highlighting"
  "fast-syntax-highlighting|https://github.com/zdharma-continuum/fast-syntax-highlighting"
)

# Extra Homebrew CLI tools: "formula|preselected(1/0)"
EXTRA_FORMULAE=(
  "jq|1" "yq|1" "ripgrep|1" "wget|1" "tmux|1" "watchman|1"
  "helm|0" "railway|0" "docker-compose|0" "protobuf|0" "xcodegen|0" "ios-deploy|0"
)

# Desktop apps: "Label|method|id|App bundle name|preselected(1/0)"
#   method: cask  → brew install --cask <id>
#           mas   → Mac App Store id (installed with `mas`, falls back to opening the App Store)
#           manual→ <id> is a URL shown in the final summary
APPS=(
  "ClickUp|cask|clickup|ClickUp|1"
  "Structured|mas|1499198946|Structured|1"
  "MongoDB Compass|cask|mongodb-compass|MongoDB Compass|1"
  "Preply|manual|https://apps.apple.com/app/id1352790442 (iPhone/iPad app — install from the App Store, 'iPhone & iPad Apps' tab)|Preply|1"
  "WhatsApp|cask|whatsapp|WhatsApp|1"
  "Notion|cask|notion|Notion|1"
  "WebStorm|cask|webstorm|WebStorm|1"
  "GoLand|cask|goland|GoLand|1"
  "Arc Browser|cask|arc|Arc|1"
  "Slack|cask|slack|Slack|1"
  "Docker Desktop|cask|docker|Docker|0"
  "Postman|cask|postman|Postman|0"
  "Figma|cask|figma|Figma|0"
  "Google Chrome|cask|google-chrome|Google Chrome|0"
  "Linear|cask|linear-linear|Linear|0"
  "Visual Studio Code|cask|visual-studio-code|Visual Studio Code|0"
)

XCODE_MAS_ID=497799835
