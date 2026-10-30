#!/bin/sh
# TS_AUTHKEY=… curl -fsSL https://raw.githubusercontent.com/SkyrunAI/get/main/enroll.sh | sh -s <user@address>
#
# Enrol a Jetson from your own machine. You are on the tailnet and the board is
# not, so you are how the key reaches it: this ssh's in over the local network
# and runs jetson.sh there with the key in its environment. The board writes it
# nowhere.
#
# The key is read from your environment and never passed as an argument: argv is
# world-readable through /proc, and this key enrols a node as tag:vehicle.
set -eu

JETSON=https://raw.githubusercontent.com/SkyrunAI/get/main/jetson.sh

[ $# -eq 1 ] || { echo "usage: enroll.sh <user@address>, with TS_AUTHKEY set" >&2; exit 1; }
[ -n "${TS_AUTHKEY:-}" ] || { echo "TS_AUTHKEY is unset" >&2; exit 1; }

# The board's own login, then sudo: L4T ships a named user and Ubuntu locks
# root, so there is nothing to log into as root until the board is on the
# tailnet. No StrictHostKeyChecking override either — this is the one moment
# the key leaves your machine, so ssh asks you to confirm the board.
#
# The key goes down the pipe ahead of the script, so it is on no command line at
# either end, and jetson.sh follows it the same way.
{
    printf "TS_AUTHKEY='%s'\nexport TS_AUTHKEY\n" "$TS_AUTHKEY"
    curl -fsSL "$JETSON"
} | ssh "$1" 'sudo sh -s'
