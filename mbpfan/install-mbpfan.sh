#!/usr/bin/env bash
# Build and install upstream mbpfan v2.5.0, which fixes both problems this
# repo used to patch around:
#   e4efe8e  Support the applesmc hwmon sysfs layout   (Linux 7.3+ fan paths)
#   4760a26  Check pwmN_enable and restore fan speeds after resume
#
# Installs ONLY the binary. Your /etc/mbpfan.conf and service unit are kept;
# they're only created if missing. The old binary is backed up next to it.
#
# Usage: sudo bash mbpfan/install-mbpfan.sh
set -euo pipefail

REPO=https://github.com/linux-on-mac/mbpfan.git
TAG=v2.5.0
COMMIT=ff73ccdffdd3ee8d4e959fbe403db04b75b0578a

[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
for t in git make gcc; do
    command -v "$t" >/dev/null || { echo "missing build tool: $t"; exit 1; }
done

# Build as the invoking user, not root, when run through sudo.
build_user=${SUDO_USER:-root}
work=$(mktemp -d)
chown "$build_user" "$work"
trap 'rm -rf "$work"' EXIT
as_user() { if [ "$build_user" = root ]; then "$@"; else runuser -u "$build_user" -- "$@"; fi; }

echo "== fetching mbpfan $TAG"
as_user git -c advice.detachedHead=false clone -q --depth 1 --branch "$TAG" "$REPO" "$work/mbpfan"
got=$(as_user git -C "$work/mbpfan" rev-parse HEAD)
if [ "$got" != "$COMMIT" ]; then
    echo "tag $TAG resolves to $got, expected $COMMIT; refusing to build"
    exit 1
fi

echo "== building"
as_user make -s -C "$work/mbpfan" >/dev/null
bin="$work/mbpfan/bin/mbpfan"
[ -x "$bin" ] || { echo "build produced no binary"; exit 1; }

if [ -e /usr/sbin/mbpfan ] && ! cmp -s "$bin" /usr/sbin/mbpfan; then
    bak=/usr/sbin/mbpfan.bak-$(date +%Y%m%d-%H%M%S)
    cp -a /usr/sbin/mbpfan "$bak"
    echo "== old binary backed up to $bak"
fi
install -m 0755 -o root -g root "$bin" /usr/sbin/mbpfan
restorecon -F /usr/sbin/mbpfan 2>/dev/null || true

if [ ! -e /etc/mbpfan.conf ]; then
    install -m 0644 "$work/mbpfan/mbpfan.conf" /etc/mbpfan.conf
    echo "== installed default /etc/mbpfan.conf"
fi
if ! systemctl cat mbpfan.service >/dev/null 2>&1; then
    install -m 0644 "$work/mbpfan/mbpfan.service" /etc/systemd/system/mbpfan.service
    systemctl daemon-reload
    systemctl enable mbpfan.service
    echo "== installed and enabled mbpfan.service"
fi

echo "== restarting mbpfan"
since=$(date '+%F %T')
systemctl restart mbpfan.service
sleep 4
systemctl is-active mbpfan.service
journalctl -u mbpfan.service --since "$since" --no-pager -o cat | grep -v '^$' | tail -5 || true

hw=$(ls -d /sys/devices/platform/applesmc.768/hwmon/hwmon* 2>/dev/null | head -1 || true)
if [ -n "$hw" ] && [ -e "$hw/fan1_target" ]; then
    for i in 1 2; do
        [ -e "$hw/fan${i}_target" ] || continue
        echo "fan$i: $(cat "$hw/fan${i}_input") rpm (target $(cat "$hw/fan${i}_target"), pwm${i}_enable=$(cat "$hw/pwm${i}_enable"))"
    done
fi
echo "done: mbpfan $TAG installed to /usr/sbin/mbpfan"
