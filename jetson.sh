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

REPO="${ROOKERY2_REPO:-git@github.com:SkyrunAI/rookery2.git}"
KEY=/etc/skyrun/id_ed25519

[ "$(id -u)" -eq 0 ] || { echo "run this as root" >&2; exit 1; }

echo "== installing what an update needs"
apt-get update -q
DEBIAN_FRONTEND=noninteractive apt-get install -yq ansible git curl

# No key, no pull. Make one, print it, and stop — a person has to add it, and
# that is the only point in this where the board waits on someone.
install -d -m 700 /etc/skyrun
if [ ! -f "$KEY" ]; then
    ssh-keygen -q -t ed25519 -N '' -C "rookery2@$(cat /etc/machine-id)" -f "$KEY"
    cat <<MSG

New deploy key. Add it READ-ONLY at:
  https://github.com/SkyrunAI/rookery2/settings/keys

$(cat "$KEY.pub")

Then run this line again.
MSG
    exit 0
fi

# The first update. It names the board from its serial, writes the identity
# record, and installs rookery2-update and rookery2-auto-update.
echo "== first update"
export GIT_SSH_COMMAND="ssh -i $KEY -o StrictHostKeyChecking=accept-new"
ansible-pull -U "$REPO" -C main -d /var/lib/rookery2 local.yml

# After the update, so it registers under the name the board just took rather
# than whatever L4T shipped with.
#
# The tag is the point: it carries the vehicle permissions and Tailscale SSH, so
# who may reach this board is an ACL on the tailnet and not a rule kept here. A
# tagged node belongs to the tag, so it does not expire with whoever enrolled it.
# TS_AUTHKEY has to be allowed to advertise the tag.
echo "== tailnet"
command -v tailscale >/dev/null || curl -fsSL https://tailscale.com/install.sh | sh
tailscale up --ssh --advertise-tags=tag:vehicle \
    ${TS_AUTHKEY:+--authkey "$TS_AUTHKEY"} --hostname "$(hostnamectl --static)"

cat <<MSG

== enrolled.

This board updates when someone runs rookery2-update. To claim it, take the
serial the update printed above and write vehicles/<name>/spec.yaml:

  class: <a class in rookery2>
  channel: canary
  serial: "<the serial, quoted>"

Commit that, then run rookery2-update here again.
MSG
