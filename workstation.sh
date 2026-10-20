#!/bin/sh
# curl -fsSL https://raw.githubusercontent.com/SkyrunAI/get/main/workstation.sh | sh

set -eu

[ "$(uname)" = Darwin ] || { echo "macOS only." >&2; exit 1; }

BIN="$HOME/.local/bin"
mkdir -p "$BIN"
export PATH="$BIN:$PATH"

if ! xcode-select -p >/dev/null 2>&1; then
    xcode-select --install
    echo "Run this again when the Command Line Tools finish installing."
    exit 1
fi

if ! command -v uv >/dev/null; then
    curl -LsSf https://astral.sh/uv/install.sh | UV_NO_MODIFY_PATH=1 sh
fi

if ! command -v gh >/dev/null; then
    arch=$(uname -m | sed 's/x86_64/amd64/')
    v=$(curl -fsSL https://api.github.com/repos/cli/cli/releases/latest | sed -n 's/.*"tag_name": "v\(.*\)".*/\1/p')
    tmp=$(mktemp -d)
    curl -fsSL -o "$tmp/gh.zip" "https://github.com/cli/cli/releases/download/v$v/gh_${v}_macOS_$arch.zip"
    unzip -q "$tmp/gh.zip" -d "$tmp"
    cp "$tmp/gh_${v}_macOS_$arch/bin/gh" "$BIN/gh"
    rm -rf "$tmp"
fi

gh auth status >/dev/null 2>&1 || gh auth login --git-protocol https --web </dev/tty
gh auth setup-git

uvx --from ansible-core ansible-pull \
    -U https://github.com/SkyrunAI/skyrun-setup.git \
    -d "$HOME/.local/share/skyrun-setup" local.yml

case ":$PATH:" in *":$BIN:"*) ;; *) echo "Add $BIN to your PATH." ;; esac
echo "Done."
