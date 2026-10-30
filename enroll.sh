#!/bin/sh
# curl -fsSL https://raw.githubusercontent.com/SkyrunAI/get/main/enroll.sh | sh -s <address> <tailnet key>
#
# Enrol a Jetson from your own machine. You are on the tailnet and the board is
# not, so you are how the key reaches it: this ssh's in over the local network
# and runs jetson.sh there with the key in its environment. The board writes it
# nowhere.
set -eu

JETSON=https://raw.githubusercontent.com/SkyrunAI/get/main/jetson.sh

[ $# -eq 2 ] || { echo "usage: enroll.sh <address> <tailnet key>" >&2; exit 1; }

# jetson.sh arrives down this pipe rather than off disk, so the one-liner works
# the same whether this script was cloned or curled.
curl -fsSL "$JETSON" |
    ssh -o StrictHostKeyChecking=accept-new "root@$1" "TS_AUTHKEY='$2' sh -s"
