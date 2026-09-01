#!/usr/bin/env bash
#
# powerbutton-guard uninstaller
# https://github.com/kreuzhofer/powerbutton-guard
#
#   curl -fsSL https://raw.githubusercontent.com/kreuzhofer/powerbutton-guard/main/uninstall.sh | sudo bash
#
# Restores systemd-logind's stock behaviour, which means a single press of the
# power button will power the machine off immediately again.
#
set -euo pipefail

say()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ok\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "must run as root (try: curl ... | sudo bash)"

say "stopping and disabling the service"
systemctl disable --now powerbutton-guard.service >/dev/null 2>&1 || true
ok "stopped"

say "removing files"
for f in /etc/systemd/system/powerbutton-guard.service \
         /etc/systemd/logind.conf.d/10-powerbutton.conf \
         /usr/local/sbin/powerbutton-guard; do
    if [ -e "$f" ]; then rm -f "$f"; ok "removed $f"; fi
done
rmdir --ignore-fail-on-non-empty /etc/systemd/logind.conf.d 2>/dev/null || true

# Config is left in place on purpose: a reinstall should pick your settings
# back up. Say so rather than deleting it silently.
if [ -e /etc/default/powerbutton-guard ]; then
    ok "kept /etc/default/powerbutton-guard (delete it by hand if you want it gone)"
fi

say "reloading systemd and logind"
systemctl daemon-reload
systemctl restart systemd-logind
ok "done"

cat <<'EOM'

  Removed. WARNING: the power button is back to the systemd default -
  a single short press will power this machine off immediately.

EOM
