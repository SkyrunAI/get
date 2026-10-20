#!/bin/sh
# curl -fsSL https://raw.githubusercontent.com/SkyrunAI/get/main/bootstrap.sh | sh -s -- <name>

set -eu

VEHICLE="${1:?usage: bootstrap.sh <vehicle-name>}"
REPO="${ROOKERY_REPO:-git@github.com:SkyrunAI/rookery.git}"

echo "== bootstrap: $VEHICLE"

hostnamectl set-hostname "$VEHICLE"

apt-get update -q
apt-get install -yq docker.io git ansible python3-docker curl

ansible-galaxy collection install community.docker >/dev/null

command -v tailscale >/dev/null || curl -fsSL https://tailscale.com/install.sh | sh
tailscale up ${TS_AUTHKEY:+--authkey "$TS_AUTHKEY"} --hostname "$VEHICLE"

install -d -m 700 /etc/skyrun
if [ ! -f /etc/skyrun/id_ed25519 ]; then
    ssh-keygen -q -t ed25519 -N '' -C "rookery@$VEHICLE" -f /etc/skyrun/id_ed25519
    echo
    echo "New deploy key. Add it READ-ONLY at:"
    echo "  https://github.com/SkyrunAI/rookery/settings/keys"
    echo
    cat /etc/skyrun/id_ed25519.pub
    echo
    echo "Then re-run: ./bootstrap.sh $VEHICLE"
    exit 0
fi

cat > /etc/systemd/system/rookery-converge.service <<UNIT
[Unit]
Description=rookery converge (ansible-pull)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
Environment=GIT_SSH_COMMAND=ssh -i /etc/skyrun/id_ed25519 -o StrictHostKeyChecking=accept-new
ExecStart=/usr/bin/ansible-pull -U ${REPO} -d /var/lib/rookery local.yml
UNIT

cat > /etc/systemd/system/rookery-converge.timer <<UNIT
[Unit]
Description=rookery converge every 15 min

[Timer]
OnBootSec=2min
OnUnitActiveSec=15min
RandomizedDelaySec=2min

[Install]
WantedBy=timers.target
UNIT

systemctl daemon-reload
systemctl enable --now rookery-converge.timer

systemctl start rookery-converge.service || true

echo
echo "== bootstrap done. Verify with:"
echo "   journalctl -u rookery-converge -n 50"
echo "   systemctl list-timers rookery-converge.timer"
