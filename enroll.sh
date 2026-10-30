#!/bin/sh
# ./enroll.sh <address> <tailnet key>
#
# Enrol a Jetson from your own machine. You are on the tailnet and the board is
# not, so you are how the key reaches it: this ssh's in and runs jetson.sh there
# with the key in its environment. The board writes it nowhere.
set -eu

[ $# -eq 2 ] || { echo "usage: $0 <address> <tailnet key>" >&2; exit 1; }

ssh -o StrictHostKeyChecking=accept-new "root@$1" "TS_AUTHKEY='$2' sh -s" \
    < "$(dirname "$0")/jetson.sh"
