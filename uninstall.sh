#!/usr/bin/env bash
# Remove mbp-resume-fix and its systemd-sleep hook.
# Usage: sudo bash uninstall.sh
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
/usr/bin/rm -fv /usr/lib/systemd/system-sleep/mbp-resume-fix /usr/local/sbin/mbp-resume-fix
echo "removed. BD_PROCHOT and mbpfan will no longer be repaired after resume."
