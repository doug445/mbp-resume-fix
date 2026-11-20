#!/usr/bin/env bash
# Install mbp-resume-fix + its systemd-sleep hook, then run it once now.
# Usage: sudo bash ~/Projects/mbp-resume-fix/install.sh
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
here=$(dirname "$(readlink -f "$0")")

/usr/bin/install -m 0755 -o root -g root "$here/mbp-resume-fix" /usr/local/sbin/mbp-resume-fix
/usr/bin/install -m 0755 -o root -g root "$here/sleep-hook" /usr/lib/systemd/system-sleep/mbp-resume-fix
/usr/sbin/restorecon -F /usr/local/sbin/mbp-resume-fix /usr/lib/systemd/system-sleep/mbp-resume-fix 2>/dev/null || true

echo "== before =="
/usr/local/sbin/mbp-resume-fix --check
echo "== fixing =="
/usr/local/sbin/mbp-resume-fix
sleep 3
echo "== after =="
/usr/local/sbin/mbp-resume-fix --check
echo "installed: /usr/local/sbin/mbp-resume-fix + /usr/lib/systemd/system-sleep/mbp-resume-fix"
