#!/usr/bin/env bash
#
# powerbutton-guard installer
# https://github.com/kreuzhofer/powerbutton-guard
#
#   curl -fsSL https://raw.githubusercontent.com/kreuzhofer/powerbutton-guard/main/install.sh | sudo bash
#
set -euo pipefail

REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/kreuzhofer/powerbutton-guard/main}"
BIN=/usr/local/sbin/powerbutton-guard
UNIT=/etc/systemd/system/powerbutton-guard.service
DROPIN_DIR=/etc/systemd/logind.conf.d
DROPIN=$DROPIN_DIR/10-powerbutton.conf
DEFAULTS=/etc/default/powerbutton-guard

say()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ok\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  !!\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- preflight
[ "$(id -u)" -eq 0 ] || die "must run as root (try: curl ... | sudo bash)"
command -v systemctl >/dev/null || die "systemd is required"
command -v python3   >/dev/null || die "python3 is required"

if ! grep -q '^N: Name="Power Button"' /proc/bus/input/devices 2>/dev/null; then
    warn "no input device named \"Power Button\" found."
    warn "the service will install but refuse to start on this machine."
fi

# Source files: a local checkout if present, otherwise fetch from GitHub.
SRC=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    maybe="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/src"
    [ -d "$maybe" ] && SRC="$maybe"
fi

fetch() { # fetch <name> <dest> <mode>
    local name="$1" dest="$2" mode="$3"
    if [ -n "$SRC" ]; then
        install -m "$mode" "$SRC/$name" "$dest"
    else
        command -v curl >/dev/null || die "curl is required for remote install"
        local tmp; tmp="$(mktemp)"
        curl -fsSL "$REPO_RAW/src/$name" -o "$tmp" \
            || die "could not download $name from $REPO_RAW"
        install -m "$mode" "$tmp" "$dest"
        rm -f "$tmp"
    fi
}

if [ -n "$SRC" ]; then say "installing from local checkout: $SRC"
else                   say "installing from $REPO_RAW"; fi

# ------------------------------------------------------------------ install
say "installing daemon and unit"
fetch powerbutton-guard          "$BIN"   0755 && ok "$BIN"
fetch powerbutton-guard.service  "$UNIT"  0644 && ok "$UNIT"

if [ -e "$DEFAULTS" ]; then
    ok "$DEFAULTS already exists - keeping your settings"
else
    fetch powerbutton-guard.default "$DEFAULTS" 0644 && ok "$DEFAULTS"
fi

say "telling logind to release the power key"
install -d -m 0755 "$DROPIN_DIR"
fetch 10-powerbutton.conf "$DROPIN" 0644 && ok "$DROPIN"

# --------------------------------------------------------------- activate
say "starting powerbutton-guard.service"
systemctl daemon-reload
systemctl enable powerbutton-guard.service >/dev/null 2>&1
# restart, not `enable --now`: on an upgrade the service is already running and
# `--now` would leave the OLD binary in memory while reporting success.
systemctl restart powerbutton-guard.service
sleep 1
systemctl is-active --quiet powerbutton-guard.service \
    || die "service failed to start - see: journalctl -u powerbutton-guard -n 30"
ok "service active and enabled at boot"

# logind only re-reads its config on restart. Sessions survive this on
# modern systemd, but say so out loud since it can be alarming over SSH.
say "restarting systemd-logind so the drop-in takes effect"
systemctl restart systemd-logind
sleep 1
systemctl is-active --quiet systemd-logind || die "systemd-logind did not come back"
eff="$(systemd-analyze cat-config systemd/logind.conf 2>/dev/null \
        | grep -E '^HandlePowerKey=' | tail -1 || true)"
[ "$eff" = "HandlePowerKey=ignore" ] \
    && ok "logind now ignores the power key" \
    || warn "expected HandlePowerKey=ignore, got '${eff:-unset}' - a reboot will apply it"

# ------------------------------------------------------------------ report
cat <<'EOM'

  Installed. The power button now behaves like this:

    one press               nothing happens
    two presses (within 2s) shutdown, with 1 minute of grace
    press during countdown  cancels the shutdown

  Cancel from anywhere:  sudo shutdown -c
  Watch it work:         journalctl -u powerbutton-guard -f
  Configure timings:     sudoedit /etc/default/powerbutton-guard
  Remove it:             see "Uninstalling" in the README

EOM
