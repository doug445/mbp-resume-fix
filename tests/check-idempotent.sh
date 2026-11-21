#!/usr/bin/env bash
# Check that every installer in this repo is idempotent: running it a second
# time must not change anything the first run left behind.
#
#   install.sh               twice -> same files, same hashes
#   uninstall.sh             twice -> second run succeeds with nothing to do
#   mbpfan/install-mbpfan.sh twice -> second run: same binary, no new backup,
#                                     mbpfan not restarted
#
# Leaves the system installed (ends with install.sh).
# Usage: sudo bash tests/check-idempotent.sh [--skip-mbpfan]
set -uo pipefail

[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
cd "$(dirname "$(readlink -f "$0")")/.." || exit 1
skip_mbpfan=0; [ "${1:-}" = --skip-mbpfan ] && skip_mbpfan=1

FILES=(/usr/local/sbin/mbp-resume-fix /usr/lib/systemd/system-sleep/mbp-resume-fix)
fail=0
ok()   { echo "  PASS  $*"; }
bad()  { echo "  FAIL  $*"; fail=1; }
snap() { for f in "$@"; do [ -e "$f" ] && sha256sum "$f" || echo "missing $f"; done; }

echo "== install.sh x2"
bash install.sh >/dev/null 2>&1 || bad "install.sh run 1 exited non-zero"
a=$(snap "${FILES[@]}")
bash install.sh >/dev/null 2>&1 || bad "install.sh run 2 exited non-zero"
b=$(snap "${FILES[@]}")
[ "$a" = "$b" ] && ok "installed files identical after second run" || bad "installed files changed"
grep -q missing <<<"$b" && bad "files missing after install" || ok "both files present"

echo "== uninstall.sh x2, then install.sh"
bash uninstall.sh >/dev/null 2>&1 || bad "uninstall.sh run 1 exited non-zero"
bash uninstall.sh >/dev/null 2>&1 && ok "second uninstall succeeds with nothing to remove" || bad "uninstall.sh run 2 exited non-zero"
for f in "${FILES[@]}"; do [ -e "$f" ] && bad "$f still present after uninstall"; done
bash install.sh >/dev/null 2>&1 || bad "reinstall exited non-zero"
c=$(snap "${FILES[@]}")
[ "$c" = "$a" ] && ok "reinstall restores identical files" || bad "reinstall differs from first install"

if [ "$skip_mbpfan" = 0 ]; then
    echo "== mbpfan/install-mbpfan.sh x2 (network + build, ~1 min)"
    bash mbpfan/install-mbpfan.sh >/dev/null 2>&1 || bad "install-mbpfan.sh run 1 exited non-zero"
    bin1=$(sha256sum /usr/sbin/mbpfan | cut -d' ' -f1)
    baks1=$(ls /usr/sbin/mbpfan.bak-* 2>/dev/null | wc -l)
    pid1=$(systemctl show -p MainPID --value mbpfan.service)
    out2=$(bash mbpfan/install-mbpfan.sh 2>&1) || bad "install-mbpfan.sh run 2 exited non-zero"
    bin2=$(sha256sum /usr/sbin/mbpfan | cut -d' ' -f1)
    baks2=$(ls /usr/sbin/mbpfan.bak-* 2>/dev/null | wc -l)
    pid2=$(systemctl show -p MainPID --value mbpfan.service)
    [ "$bin1" = "$bin2" ] && ok "binary unchanged on second run" || bad "binary changed on second run (build not reproducible?)"
    [ "$baks1" = "$baks2" ] && ok "no new backup on second run ($baks2 total)" || bad "second run made a new backup ($baks1 -> $baks2)"
    [ "$pid1" = "$pid2" ] && ok "mbpfan not restarted on second run (pid $pid2)" || bad "mbpfan restarted on second run ($pid1 -> $pid2)"
    grep -q "no changes made" <<<"$out2" && ok "second run reports no changes" || bad "second run did not report 'no changes made'"
fi

echo
if [ "$fail" = 0 ]; then echo "ALL IDEMPOTENT"; else echo "SOME CHECKS FAILED"; fi
exit "$fail"
