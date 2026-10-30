#!/bin/sh
# curl -fsSL https://raw.githubusercontent.com/SkyrunAI/get/main/update.sh | sh -s <user@address>
#
# Update a board you can reach but cannot Tailscale SSH into as root — one that
# is on the tailnet but not yet tagged, or one carrying an update command older
# than the fleet's. It puts the current command there and runs it; the board
# fetches its own state, as it always does.
#
# Pass ssh anything it needs in SSH_OPTS, e.g. SSH_OPTS="-i ~/.ssh/board_key".
# A board whose sudo wants a password takes it in SUDO_PW, the same way.
set -eu

FLEET="${ROOKERY2_FLEET:-rookery2.tailbff67c.ts.net:5000}"

[ $# -eq 1 ] || { echo "usage: update.sh <user@address>" >&2; exit 1; }

# The board's own login, then sudo: a board that is not yet tagged has no
# Tailscale SSH, and L4T locks root.
#
# Installed from the state the fleet serves rather than from here, so there is
# one copy of the update command and it is the fleet's. A board whose own copy
# is older than the fleet's cannot update itself out of that — this is the one
# nudge that breaks it, and it is idempotent after.
REMOTE='
set -eu
d=$(mktemp -d)
curl -fsS "https://$FLEET/state" | tar -xzf - -C "$d"
install -m 755 "$d/ansible/roles/update/files/rookery2-update" /usr/local/sbin/
rm -rf "$d"
rookery2-update
'
# sudo -S reads its password from the first line and hands the rest to the
# shell, so a password rides the same stream as the script. A board with
# passwordless sudo wants no first line.
if [ -n "${SUDO_PW:-}" ]; then
    elevate='sudo -S -p "" sh -s'
    password="$SUDO_PW
"
else
    elevate='sudo sh -s'
    password=""
fi

{
    printf '%s' "$password"
    printf 'FLEET=%s\n' "$FLEET"
    printf '%s' "$REMOTE"
} | ssh ${SSH_OPTS:-} "$1" "$elevate"
