#!/bin/sh
# What jetson.sh does to the key a board recovers with.
#
# The board keeps that key, so the one thing that must never happen is losing a
# working key to one that does not join. These run jetson.sh the way a board
# does, with every command it shells out to answering the way the case says the
# world is.
#
# Destructive: it writes /etc/skyrun and /usr/local/sbin. The CI runner is
# disposable.
set -eu

KEY=/etc/skyrun/tailnet-authkey
BIN=/tmp/stubs
OLD=tskey-the-key-this-board-already-had
NEW=tskey-the-replacement

no() { echo "FAIL: $1"; exit 1; }

# Everything jetson.sh reaches for. apt, pip and the galaxy do nothing; curl
# answers the fleet with a tar holding the update command, which jetson.sh
# installs and runs.
stubs() {
    rm -rf "$BIN"; mkdir -p "$BIN"
    for c in apt-get python3 ansible-galaxy docker; do
        printf '#!/bin/sh\nexit 0\n' > "$BIN/$c"
    done
    printf '#!/bin/sh\necho ci-board\n' > "$BIN/hostnamectl"
    cat > "$BIN/curl" <<'STUB'
#!/bin/sh
out=""
while [ $# -gt 0 ]; do
    case "$1" in -o) out="$2"; shift 2 ;; *) shift ;; esac
done
[ -n "$out" ] && cp /tmp/state.tar.gz "$out" && exit 0
cat /tmp/state.tar.gz
STUB
    chmod 755 "$BIN"/*
}

# The fleet's answer: a tree holding the update command jetson.sh installs.
state() {
    rm -rf /tmp/state; mkdir -p /tmp/state/ansible/roles/update/files
    printf '#!/bin/sh\nexit 0\n' \
        > /tmp/state/ansible/roles/update/files/rookery2-update
    tar -czf /tmp/state.tar.gz -C /tmp/state .
}

# $1 is what `tailscale up` does, $2 what `tailscale status` reports.
tailscale_says() {
    cat > "$BIN/tailscale" <<STUB
#!/bin/sh
case "\$1" in
status) echo '{"BackendState": "$2"}'; exit 0 ;;
up)     [ "$1" = ok ] && exit 0
        echo "invalid key: unauthorized" >&2; exit 1 ;;
esac
exit 0
STUB
    chmod 755 "$BIN/tailscale"
}

run() {
    state
    ( PATH="$BIN:$PATH"; export PATH TS_AUTHKEY="$1"; sh jetson.sh >/tmp/run.log 2>&1 )
}

stubs
install -d -m 755 /etc/skyrun

echo "== a board with no key gets the one it enrolled with"
rm -f "$KEY"
tailscale_says ok NeedsLogin
run "$NEW" || no "enrolling a fresh board failed: $(tail -3 /tmp/run.log)"
[ "$(cat "$KEY")" = "$NEW" ] || no "the key the board joined with was not kept"
echo "   ok"

echo "== a replacement that will not join does not replace the key"
printf '%s\n' "$OLD" > "$KEY"; chmod 600 "$KEY"
tailscale_says refuse NeedsLogin
run "$NEW" && no "jetson.sh reported success on a key that would not join"
[ "$(cat "$KEY")" = "$OLD" ] || no "a key that would not join replaced a working one"
[ ! -e "$KEY.staged" ] || no "the refused key was left staged on the board"
echo "   ok"

echo "== a replacement that joins does replace the key"
printf '%s\n' "$OLD" > "$KEY"; chmod 600 "$KEY"
tailscale_says ok NeedsLogin
run "$NEW" || no "enrolling with a good key failed: $(tail -3 /tmp/run.log)"
[ "$(cat "$KEY")" = "$NEW" ] || no "the key that joined was not kept"
echo "   ok"

echo "== on a board already on the tailnet, the key is kept, because nothing checked the new one"
# `tailscale up` returns at once on a Running node without asking the control
# server, so its success says nothing about the key it was handed.
printf '%s\n' "$OLD" > "$KEY"; chmod 600 "$KEY"
tailscale_says ok Running
run "$NEW" || no "re-running on a healthy board failed: $(tail -3 /tmp/run.log)"
[ "$(cat "$KEY")" = "$OLD" ] || no "an unchecked key overwrote the one that works"
echo "   ok"

echo "== on a stopped board the key is kept too: it is still logged in"
# Stopped is a client that is logged in and switched off. Starting it uses the
# login it already had, so the key it was handed went just as unchecked.
printf '%s\n' "$OLD" > "$KEY"; chmod 600 "$KEY"
tailscale_says ok Stopped
run "$NEW" || no "re-running on a stopped board failed: $(tail -3 /tmp/run.log)"
[ "$(cat "$KEY")" = "$OLD" ] || no "an unchecked key overwrote the one that works"
echo "   ok"

echo "== a board on the tailnet with no key gets one, unchecked or not"
# Every board enrolled before the key was kept is this board. An unchecked key
# beats no key: without one it cannot log itself back in at all.
rm -f "$KEY"
tailscale_says ok Running
run "$NEW" || no "seeding a healthy board failed: $(tail -3 /tmp/run.log)"
[ "$(cat "$KEY")" = "$NEW" ] || no "a board with no key was left with none"
echo "   ok"

echo "== the key is root-only"
[ "$(stat -c %a "$KEY")" = 600 ] || no "the key is $(stat -c %a "$KEY"), not 600"
echo "   ok"

echo "== an interactive enrolment writes no key"
rm -f "$KEY"
tailscale_says ok NeedsLogin
state
( PATH="$BIN:$PATH"; export PATH; unset TS_AUTHKEY; sh jetson.sh >/tmp/run.log 2>&1 ) ||
    no "interactive enrolment failed: $(tail -3 /tmp/run.log)"
[ ! -e "$KEY" ] || no "an interactive enrolment invented a key"
echo "   ok"
