#!/bin/sh
# curl -fsSL https://raw.githubusercontent.com/SkyrunAI/get/main/jetson.sh | sh
#
# Enrol a Jetson into rookery2. A Jetson arrives with L4T already on it, so
# there is nothing to bake; this does the same job on the running board.
#
# It takes no vehicle name. The serial is the join key, and the update reads it
# off the silicon. A board becomes a vehicle when a manifest claims that serial.
#
# Everything this does is a prerequisite for running an update. The update owns
# the rest, so that enrolment is described in one place and this stays short.
set -eu

FLEET="${ROOKERY2_FLEET:-rookery2.tailbff67c.ts.net:5000}"

[ "$(id -u)" -eq 0 ] || { echo "run this as root" >&2; exit 1; }

# ansible comes from pip, not the distro. Ubuntu 22.04 ships ansible 2.10, whose
# filter plugins import environmentfilter — removed in Jinja2 3.1 — and a Jetson
# that has ever pip installed anything already has a newer Jinja2, so every
# template fails at parse time. --break-system-packages is accepted whether or
# not the distro marks its python externally managed.
echo "== installing what an update needs"
apt-get update -q
DEBIAN_FRONTEND=noninteractive apt-get install -yq curl python3-pip python3-requests
python3 -m pip install --break-system-packages --upgrade ansible-core
# The play starts containers through community.docker, which ansible-core does
# not carry; its modules reach the daemon through python3-requests. Without the
# collection the update fails while loading, before it names the board.
ansible-galaxy collection install community.docker

# A class runs what it names in containers, and the update stops on a board with
# no runtime rather than install one. A runtime already here is kept: on a
# Jetson it may be the vendor's.
command -v docker >/dev/null || DEBIAN_FRONTEND=noninteractive apt-get install -yq docker.io

# Before the update, because the tailnet is what authorises the pull: the board
# holds no credential for the fleet, and being on the network is the whole of
# its claim (ADR 0001).
#
# The tag is the point: it carries the vehicle permissions and Tailscale SSH, so
# who may reach this board is an ACL on the tailnet and not a rule kept here. A
# tagged node belongs to the tag, so it does not expire with whoever enrolled it.
# TS_AUTHKEY has to be allowed to advertise the tag, and it has to be
# reusable, pre-approved and NOT ephemeral. Tailscale deletes an ephemeral
# node once its board has been off long enough, and the board then has no
# node to come back to.
echo "== tailnet"
command -v tailscale >/dev/null || curl -fsSL https://tailscale.com/install.sh | sh

# The board keeps this key, and it is the only thing it keeps. Tailscale
# deleted three nodes while their boards were powered off, and each board came
# back needing a login nobody was there to give it (rookery2#274). The first
# update below installs rookery2-tailnet, which reads the key from here every
# minute until the board is back on the tailnet.
#
# Staged first, kept only if the join works. A board that already has a working
# key must not lose it to one that does not join: it would then be a board that
# cannot recover, which is the fault this whole thing exists to fix.
#
# Root-only, created empty at that mode before anything is written into it, so
# the key is never in a world-readable file even for an instant. printf is the
# shell's own and tailscale reads the file, so the key is on no command line at
# either end — argv is world-readable through /proc.
KEY=/etc/skyrun/tailnet-authkey
STAGED=$KEY.staged
trap 'rm -f "$STAGED"' EXIT

if [ -n "${TS_AUTHKEY:-}" ]; then
    install -d -m 755 /etc/skyrun
    install -m 600 /dev/null "$STAGED"
    printf '%s\n' "$TS_AUTHKEY" > "$STAGED"
fi

# Whether this board was already on the tailnet, read before the join. It
# decides whether the join below says anything about the key: see the promotion.
was=$(tailscale status --json 2>/dev/null |
    sed -n 's/.*"BackendState"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)

tailscale up --ssh --advertise-tags=tag:vehicle \
    ${TS_AUTHKEY:+--auth-key="file:$STAGED"} --hostname "$(hostnamectl --static)"

# `tailscale up` returns at once on a node that is already Running, without
# asking the control server anything, so on such a board it is no evidence the
# key is good. Keep what that board already has rather than overwrite a working
# key with one nothing checked — unless it has none, which is every board
# enrolled before the key was kept at all.
if [ -n "${TS_AUTHKEY:-}" ]; then
    if [ "$was" != Running ] || [ ! -e "$KEY" ]; then
        mv -f "$STAGED" "$KEY"
        echo "== the key this board recovers with is at $KEY"
    else
        echo "== already on the tailnet, so this key was never checked."
        echo "   Keeping the one at $KEY. To replace it, see rookery2's"
        echo "   docs/provisioning-a-board.md."
    fi
fi

# The fleet hands this board its desired state, which carries the update command
# itself. Running that command rather than repeating what it does means one
# answer to how a board updates instead of two that drift.
# tailscale up returns before MagicDNS can answer, and the next line asks for
# the fleet by name. Found re-enrolling weka: the join succeeded and the update
# died on "Could not resolve host: rookery2" a second later.
echo "== waiting for the fleet"
i=0
while [ $i -lt 30 ] && ! curl -fsS -o /dev/null --max-time 5 "https://$FLEET/state"; do
    i=$((i + 1)); sleep 2
done

echo "== first update"
install -d /var/lib/rookery2
curl -fsS "https://$FLEET/state" | tar -xzf - -C /var/lib/rookery2
install -m 755 /var/lib/rookery2/ansible/roles/update/files/rookery2-update /usr/local/sbin/
rookery2-update

# The update names the board from its serial, and the tailnet node took whatever
# name L4T shipped with. Rename it, so the fleet knows this board by the name its
# own silicon gave it — which is also the name fetch matches a caller against.
#
# `set`, not a second `up`: a board reached only over the tailnet should not be
# asked to reauthenticate to change one field.
tailscale set --hostname="$(hostnamectl --static)"

cat <<MSG

== enrolled.

This board updates when someone runs rookery2-update. To claim it, take the
serial the update printed above and write vehicles/<name>/spec.yaml:

  class: <a class in rookery2>
  channel: canary
  serial: "<the serial, quoted>"

Commit that, then run rookery2-update here again.
MSG
