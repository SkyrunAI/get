#!/bin/sh
# curl -fsSL https://raw.githubusercontent.com/SkyrunAI/get/main/extras.sh | sh
#
# Add GitButler, SkillOpt-Sleep and iTAK setup after workstation.sh.
#
# Installing the skyrun-extras plugin is the whole switch. Setup reads the list
# of installed plugins and runs the extras when it sees that name, so
# every converge from here on keeps them.

set -eu

[ "$(uname)" = Darwin ] || { echo "macOS only." >&2; exit 1; }

BIN="$HOME/.local/bin"
export PATH="$BIN:$PATH"

command -v claude >/dev/null || {
    echo "Claude Code is missing. Run workstation.sh first." >&2
    exit 1
}

# Refresh the marketplace before installing Extras.
claude plugin marketplace update skyrun-local

claude plugin install skyrun-extras@skyrun-local || {
    echo "Could not install skyrun-extras from skyrun-local. Check the error above." >&2
    exit 1
}

uvx --from ansible-core ansible-pull \
    -U https://github.com/SkyrunAI/skyrun-setup.git \
    -d "$HOME/.local/share/skyrun-setup" local.yml

echo "Skyrun Extras setup finished."
