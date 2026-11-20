# mbp-resume-fix

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Free and open source](https://img.shields.io/badge/Free%20and%20open%20source-brightgreen.svg)](LICENSE)
[![Platform: MacBookPro11,x](https://img.shields.io/badge/platform-MacBook%20Pro%2011%2Cx%20(2013%E2%80%932014)-lightgrey.svg)](#tested-on)

Fixes what suspend/resume (closing and reopening the lid) breaks on Intel
MacBook Pros running Linux: **a CPU stuck at 800 MHz** and **fans stuck at
minimum while the CPU cooks**.

## The problem

After every wake, two things go wrong:

1. **BD_PROCHOT gets stuck.** The SMC leaves *bidirectional PROCHOT* asserted
   (bit 0 of `MSR_POWER_CTL`, `0x1FC`). Every core is then pinned at about
   800 MHz no matter how cool the CPU is, and `thermal_throttle` counters don't
   move because this isn't thermal throttling. The whole desktop crawls, and
   every process looks like it's using 3× the CPU it should.
2. **The fans stop following the temperature.** The SMC resets the fan targets
   on wake. [mbpfan](https://github.com/linux-on-mac/mbpfan) caches the last
   speed it wrote and only writes when that value changes, so it never puts its
   speed back (fixed upstream in mbpfan 2.5.0, see [mbpfan](#mbpfan)). On the
   machine this was written for, the fans sat at 2000 rpm
   while the package hit 100 °C and the kernel's `intel_powerclamp` started
   injecting forced idle time.

The two together are nasty: the CPU is too slow to finish work, too hot to
speed up, and nothing is cooling it.

## What it does

A `systemd-sleep` hook runs after every resume, waits 3 s for the SMC to settle,
then:

- clears BD_PROCHOT on every CPU where it's set (only if it's set), and
- runs `systemctl try-restart mbpfan`. That makes mbpfan re-read the
  temperature and write the fan speed again. It's a no-op if mbpfan is stopped
  on purpose (for example while something else is holding the fans at maximum).

Each run logs to the journal under `mbp-resume-fix`.

## mbpfan

Both mbpfan problems on recent kernels are fixed upstream in
**[mbpfan v2.5.0](https://github.com/linux-on-mac/mbpfan/releases/tag/v2.5.0)**
(2026-11-17):

- `e4efe8e` *Support the applesmc hwmon sysfs layout*. Linux 7.3 moved the
  applesmc fan files to `hwmon/hwmonN/` (`fanN_output` → `fanN_target`,
  `fanN_manual` → `pwmN_enable`). Older mbpfan reports "could not detect any
  fan" and leaves the Mac to run hot.
- `4760a26` *Check pwmN_enable and restore fan speeds after resume*, which is
  the stale fan speed bug described above.

If your distro ships an older mbpfan, or you're running a hand-patched build,
this installs the pinned upstream release:

```bash
sudo bash mbpfan/install-mbpfan.sh
```

It clones tag `v2.5.0`, refuses to build unless the tag resolves to commit
`ff73ccd`, builds as your user, and installs **only** `/usr/sbin/mbpfan`. The
old binary is backed up next to it. Your `/etc/mbpfan.conf` and service unit
are left alone, and are only created if they're missing.

With mbpfan ≥ 2.5.0 the hook's `try-restart` is just a backstop. It stays because
it also covers older mbpfan versions and an SMC that finishes resetting the fans
after mbpfan has already re-applied them.

## Install

```bash
git clone https://github.com/doug445/mbp-resume-fix.git
cd mbp-resume-fix
sudo bash install.sh
```

`install.sh` installs:

| File | Purpose |
|---|---|
| `/usr/local/sbin/mbp-resume-fix` | the fixer (Python 3, no dependencies) |
| `/usr/lib/systemd/system-sleep/mbp-resume-fix` | runs it on every resume |

It also runs the fixer once immediately and prints the state before and after.

## Check it

```bash
sudo mbp-resume-fix --check              # report only, change nothing
journalctl -t mbp-resume-fix -b          # what it did after each wake
```

A wake where the bug happened looks like this:

```
BD_PROCHOT set on 8 cpu(s); avg clock 3020 MHz
cleared BD_PROCHOT
mbpfan try-restart rc=0
```

## Uninstall

```bash
sudo bash uninstall.sh
```

## Safety

Clearing BD_PROCHOT means the CPU **ignores the external "slow down" signal**
from the SMC/EC. The CPU's own thermal protection (TjMax / TCC, about 100 °C)
still works, so it can't overheat itself. But if the SMC was asserting PROCHOT
for a real reason, such as an underpowered charger or a failing battery, that
safety net is off until the next wake. The hook only acts after a resume, never
at boot, and only on CPUs where the bit is actually set.

Writing MSRs needs the `msr` module (the fixer loads it) and doesn't work under
kernel lockdown (`/sys/kernel/security/lockdown` must be `[none]`).

## GPU driver: use nouveau, never NVIDIA's driver on Kepler

The MacBook Pro 11,3 has an NVIDIA GeForce GT 750M, a **Kepler** GPU. **Use the
open-source nouveau driver. Do not install NVIDIA's proprietary driver on a
Kepler Mac, ever.**

The only NVIDIA driver that still supports Kepler is the end-of-life
470xx legacy branch, and on this hardware it's unworkable:

- The test machine has always run nouveau, and is stable on Plasma 6 (Wayland)
  with kernel 7.3.
- An identical MacBook Pro that ran the NVIDIA 470xx legacy driver became
  unusable: KWin compositor corruption, plus other major problems.

nouveau is in the mainline kernel, keeps working across kernel upgrades, and
doesn't need out-of-tree modules. This repo was developed and tested on
nouveau only. If you're coming from the NVIDIA driver, remove it completely,
including `akmod-nvidia*` / `nvidia-*` packages and any `nouveau` blacklist in
`/etc/modprobe.d/` or the kernel command line, before chasing thermal or resume
problems. A broken GPU driver can cause both.

## Tested on

- MacBookPro11,3 (Late 2013, i7-4850HQ, GT 750M on nouveau), Fedora 45,
  kernel 7.3, mbpfan 2.5.0 (built with `mbpfan/install-mbpfan.sh`).

Other Haswell/Broadwell MacBook Pros with the same symptoms should behave the
same way, but haven't been tested.

## License

MIT, see [LICENSE](LICENSE).
