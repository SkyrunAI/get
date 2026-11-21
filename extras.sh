#!/bin/sh
# curl -fsSL https://raw.githubusercontent.com/SkyrunAI/get/main/extras.sh | sh
#
# Add the extras to a Mac that already ran workstation.sh: Pinrail, GitButler
# and SkillOpt-Sleep, plus the rules that tell Claude to ask through Pinrail.
#
# Installing the skyrun-extras plugin is the whole switch. Setup reads the list
# of installed plugins and installs the three apps when it sees that name, so
# every converge from here on keeps them.

set -eu

[ "$(uname)" = Darwin ] || { echo "macOS only." >&2; exit 1; }

BIN="$HOME/.local/bin"
export PATH="$BIN:$PATH"

command -v claude >/dev/null || {
    echo "Claude Code is missing. Run workstation.sh first." >&2
    exit 1
}

# The marketplace is a folder on this Mac, ~/github/SkyrunAI/skyrun-setup.
# Re-read it, in case setup has pulled a newer kit since Claude last looked.
claude plugin marketplace update skyrun-local

claude plugin install skyrun-extras@skyrun-local || {
    echo "skyrun-local has no skyrun-extras yet, so your kit copy is behind." >&2
    echo "Run workstation.sh to bring it up to date, then run this line again." >&2
    exit 1
}

uvx --from ansible-core ansible-pull \
    -U https://github.com/SkyrunAI/skyrun-setup.git \
    -d "$HOME/.local/share/skyrun-setup" local.yml

echo "Done. Open Pinrail and run its Connect step for Claude and Codex."
