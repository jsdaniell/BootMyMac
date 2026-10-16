#!/bin/bash
# One-line bootstrap for a fresh Mac (no git needed yet):
#
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/jsdaniell/BootMyMac/main/install.sh)"
#
# Downloads the repository to ~/.bootmymac/src and runs boot.sh. Extra args are passed through.

set -e
REPO="jsdaniell/BootMyMac"
BRANCH="${BOOTMYMAC_BRANCH:-main}"
DEST="$HOME/.bootmymac/src"

echo "› Downloading BootMyMac ($REPO@$BRANCH)…"
rm -rf "$DEST.tmp"
mkdir -p "$DEST.tmp"
curl -fsSL "https://github.com/$REPO/archive/refs/heads/$BRANCH.tar.gz" | tar -xz -C "$DEST.tmp" --strip-components=1
rm -rf "$DEST"
mv "$DEST.tmp" "$DEST"
chmod +x "$DEST/boot.sh" "$DEST"/claude/hooks/*.sh

exec /bin/bash "$DEST/boot.sh" "$@" </dev/tty
