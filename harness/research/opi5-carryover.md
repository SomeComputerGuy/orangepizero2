# What carries over from the Orange Pi 5 project (~/orangepi5) to the Zero2 build

Research snapshot 2026-11-01. Read-only survey of `~/orangepi5`, `~/orangepi5-github`, and the
opi5 Claude memory (`~/.claude/projects/-home-aruni-orangepi5/memory/*.md`). Nothing there was
modified.

## 0. The one framing fact

**The opi5 project does not use the Armbian build framework.** Its image is built by its own
scripts: `mmdebstrap` rootfs (`scripts/build-image.sh`), kernel debs from a Ubuntu-config kernel
(`scripts/build-kernel.sh`), TF-A + mainline U-Boot (`scripts/build-uboot.sh`). There is no
Armbian clone, no `userpatches/`, no `compile.sh` run anywhere under `~/orangepi5`.

Their only Armbian touchpoint is a **read-only audit of Armbian's rockchip64-7.3 patch tree at
commit `fb22cb0f1940bfeaabdfefd5a05a3ccb70087734`** (the same base our branch
`stonking-orangepizero2` sits on), cherry-picking Armbian patches into their own kernel:
`~/orangepi5/work/_out/armbian/REPORT.md` + `patches/0001..0017`, kernel worktree
`~/orangepi5/build/wt-armbian` (branch `opi5/armbian`, tip `8216cd04bf6a`). The memory file
`opi5-armbian-contrib.md` says "Nothing opened yet; user sends/approves all PRs".

So for question 1 (Armbian framework fixes) the honest answer is: **they made none**. Everything
below is what transfers anyway: host-toolchain fixes they solved differently, generic 7.3 /
2026.10 / Ubuntu 26.10 findings, and harness and patch-hygiene practices.

Shared context that makes the carryover cheap: same host (claudebox, Ubuntu 26.10 x86_64), same
user and git identity, same Meross account (plug UUIDs differ), two CP2102 adapters that both
report serial "0001" (hence our `harness/99-opiz2-serial.rules` matching `KERNELS=="3-4"`).

---

## 1. Build-framework / host-toolchain fixes (compare with our `fb22cb0..HEAD`)

Our six commits: `9ff4ce3` (stonking distro + host release), `93e24f8` (print-server profile),
`f318c9c` (U-Boot OpenSSL 4), `ef99c0c` (base-files json fallback), `971dd01` (uutils `ln -f`
in chroot), `794f1d4` (dbus launch-helper absent).

| Topic | opi5 handling | Ours | Verdict / action |
|---|---|---|---|
| **OpenSSL 4 removed ENGINE -> U-Boot host tools fail to link** | Kconfig-only: `scripts/config --disable TOOLS_KWBIMAGE --disable TOOLS_LIBCRYPTO` after `make <defconfig>` (`~/orangepi5/scripts/build-uboot.sh` lines ~"OpenSSL 4"). Comment: "kwbimage, a Marvell-only image format, force-selects libcrypto". No source patch, FIT signing tools dropped (they don't sign). | Source patch `patch/u-boot/v2026.10-sunxi64/tools-rsa-sign-openssl4-engine-stubs.patch` (`#define OPENSSL_ENGINE_STUBS` in `lib/rsa/rsa-sign.c`). Keeps libcrypto. | Keep ours (less functionality lost). Two gaps to close: (a) ours lives only in `v2026.10-sunxi64/`; every other `patch/u-boot/v2026.10*` dir (rockchip64 `v2026.10`, `v2026.10-rtd129x`, `v2026.10-sunxi`) hits the same link failure on a 26.10 host -> for an Armbian PR either copy the patch into each dir or do it framework-wide in `lib/functions/compilation/uboot.sh` via `scripts/config` (hooks `pre_config_uboot_target` / `post_config_uboot_target` exist, lines 94/206) gated on host OpenSSL >= 4, using their Kconfig trick as the fallback when a tree lacks the stubs. (b) Check whether upstream U-Boot master already has an OpenSSL-4 fix to cite in the patch header. |
| uutils coreutils `ln -f` needs `/dev/urandom` in chroot | Not hit: their customize hook runs host-side on `$R/...` paths (`install -D`, `rsync --chown`) and only chroots for `dpkg -i`/`apt-get clean`/`debconf-set-selections`. | `971dd01` moves the `ln` to the host. | Same conclusion. General rule worth adopting in any further Armbian fix: prefer host-side file ops on `${SDCARD}/...` over `chroot_sdcard` for pure file manipulation under 26.10's rust coreutils. |
| `dbus-daemon-launch-helper` missing (dbus-broker is 26.10's default) | Their boot audit confirms dbus-broker is the system bus in 26.10 (`dbus-broker-launch: Invalid user name ...` lines, `work/_out/boot-failures/RESULTS.md`). | `794f1d4` skips the chown. | Confirmed correct. |
| base-files GHA json lacks new release | N/A (mmdebstrap pulls from ports directly). | `ef99c0c` Packages.xz fallback. | Ours only; upstreamable to Armbian as-is. |
| Keyring handling | `--keyring=/usr/share/keyrings/ubuntu-archive-keyring.gpg` from the host's `ubuntu-keyring` ("host's ubuntu-keyring must know that release", README). | Armbian `fetch_distro_keyring` path extended for stonking in `9ff4ce3`. | Nothing to copy. |
| qemu-user-binfmt vs qemu-user-static | `install-deps.sh` installs `qemu-user-binfmt arch-test` on 26.10. | `9ff4ce3` adds stonking to the `qemu-user-binfmt` case. | Corroborates ours. |
| SWIG / pyelftools / python 3.14 for U-Boot binman | `install-deps.sh`: `swig python3-pyelftools python3-setuptools python3-dev libgnutls28-dev uuid-dev`. No breakage recorded; they run all helper Python with `python3 -I`. | Armbian `prepare-host.sh` already has swig, libgnutls28-dev, pyelftools via requirements.txt. | Nothing to do. Our own `v2026.10-sunxi64/README.md` already documents the SWIG 4.3 pylibfdt break that forced sunxi off v2024.01. |
| BTF / pahole | Lesson, not a fix: `CONFIG_DEBUG_INFO_BTF_MODULES=y` without `MODULE_ALLOW_BTF_MISMATCH` means a new `vmlinuz` alone rejects every module (BTF -22) and the board sticks in initramfs (`opi5-board-deployed-state.md`). Always install the whole linux-image deb. | `config/kernel/linux-sunxi64-edge.config` has `CONFIG_DEBUG_INFO_BTF=y` (so BTF_MODULES defaults y). Armbian installs via deb. | Add to our board-test rules: never copy a bare `Image` to `/boot`; always `dpkg -i` the `linux-image-edge-sunxi64` deb; post-boot check `dmesg | grep -cE "failed to validate module|BTF.*-22"` == 0 (see §3). |
| dtc / kernel packaging / debootstrap | Nothing relevant: they don't package through Armbian. `scripts/customize-rootfs.sh` does the usual image hygiene (clear `/etc/machine-id`, drop ssh host keys, `apt-get clean`, remove proxy conf, re-enable man-db auto-update). | Armbian already does equivalents. | Nothing to do. |
| ccache | `docs/BUILD-CACHE.md`, `feedback-kernel-build-cache.md`: near-0% hit rate root-caused to `compiler_check=mtime` on a wrapper rewritten every run -> fixed with `CCACHE_COMPILERCHECK=string:<hash>`; and with `-g` ccache keys on cwd/absolute paths, so builds in different O= dirs never share entries. | `kernel-check/build-kernel.sh` uses `CCACHE_DIR=armbian-build/cache/ccache` but untars into `kernel-check/work/linux-7.3.1` while Armbian builds in `cache/sources/linux-kernel-worktree/...`. With DWARF/BTF on (`-g`), those two never share hits. | Set `CCACHE_BASEDIR`/`hash_dir=false` (or `CCACHE_NOHASHDIR=1`) in `kernel-check/build-kernel.sh` and check `ccache -s -v` direct-vs-preprocessed misses after the next run. Low priority unless kernel-check time matters. |
| Rootless package-set preflight | `build-image.sh --rootfs-tar FILE` runs `mmdebstrap --mode=unshare --variant=apt` just to prove the package set resolves and hooks run, in minutes, no sudo. | We only find out inside a full Armbian build. | Worth a 20-line `scripts/preflight-packages.sh`: `mmdebstrap --mode=unshare --variant=apt --arch=arm64 --include="$(tr '\n' , < armbian-build/config/cli/stonking/main/packages.additional)" stonking /tmp/x.tar "deb http://ports.ubuntu.com/ubuntu-ports stonking main restricted universe multiverse"`. Catches renamed/removed printer-driver packages before a 40-minute build. |
| apt-cacher-ng auto-detect | Probes `127.0.0.1:3142` and sets `Acquire::http::Proxy`; `OPI5_APT_PROXY=none` disables. | Armbian has its own apt-cacher-ng handling. | Nothing to do. |

Net result for question 1: **nothing they fixed that we have not**; the one thing they did
"better" is the Kconfig-only OpenSSL approach as a zero-source-patch fallback, and the one thing
we should widen is the OpenSSL patch's reach across all `v2026.10*` U-Boot dirs before offering it
to Armbian.

---

## 2. Generic (SoC-independent) Linux 7.3 / U-Boot 2026.10 / Ubuntu 26.10 findings

### 2.1 Kernel 7.3

| Finding | Source in ~/orangepi5 | Applies to Zero2? | Where it would go |
|---|---|---|---|
| **`PM: suspend: Do not call suspend_ops->begin()/end() for s2idle`** (upstream `4785d5faa935`, 7.4; Fixes `7602c0ec0bbf` which is in v7.3). On v7.3 every s2idle runs with `pm_suspend_via_firmware()==true` via PSCI `begin`, so drivers take "firmware cuts power" paths. | `work/_out/patch-audit/REPORT.md` item 6 | Yes if we test s2idle (H616 uses PSCI too). Generic. | `armbian-build/patch/kernel/archive/sunxi-7.3/patches.armbian/` + `series.conf`; upstreamable to Armbian as a `general-*` backport until it lands in 7.3.y stable. Check `linux-7.3.y` first. |
| **DPM watchdog on prepare/late/early/noirq/complete** (upstream `33392343c74e`, 7.4) + `CONFIG_DPM_WATCHDOG=y`: names the device that hangs in suspend instead of a silent wedge. | patch-audit item 18 | Yes, for suspend testing only. | Test-kernel config fragment / userpatches kernel config; not for the shipped image. |
| **rtc core: minute-resolution alarm rounds down into the past** (`rtcwake -s 15` never arms the alarm; system sleeps forever). Patch `drivers/rtc/interface.c`. | `work/_out/suspend-k10/patches/0001-rtc-Don-t-lose-a-minute-resolution-alarm-that-rounds.patch`, `suspend-k10/RESULTS.md` | Probably not the bug (sun6i RTC alarm has seconds resolution), but the **test lesson** does: always aim wake alarms at the next full minute + 1 and verify `/proc/driver/rtc` shows `alarm_IRQ: yes` before trusting a suspend cycle. | `harness/` suspend test script, if/when we do suspend. |
| **8250 console is nbcon in 7.3**: during `device_shutdown()` printk only queues to the printer kthread, which dies with the stall, so shutdown/reboot hangs print nothing. Synchronous console for debugging: `earlycon=uart8250,mmio32,<UART0 base> keep_bootcon initcall_debug ignore_loglevel printk.devkmsg=on`. | `work/_out/shutdown-hang/RESULTS.md` "Why the initcall_debug attempt showed no shutdown lines" | Yes, generic. For H616 use UART0 at `0x05000000`. | Document in `harness/` debugging notes; add as an `armbianEnv.txt` `extraargs` recipe for reboot/poweroff-hang triage. |
| `watchdog0: watchdog did not stop!` at shutdown is expected when systemd's `RebootWatchdogSec` keeps the wdt armed (no patch). `sync_state() pending due to ...` dev_info lines at the deferred-probe timeout are expected for consumers whose modules load later. | `work/_out/FIXLIST.md` 19b, `board-hygiene/RESULTS.md` §7 | Yes: saves triage time when reading our dmesg. | Note in the board-health checklist's "known-benign" list. |
| `kernel.panic=10` / `panic=10 oops=panic` + systemd hardware watchdog (`RuntimeWatchdogSec=30s RebootWatchdogSec=60s`, Ubuntu Core style) so an unattended board reboots itself. They later **removed** `panic=` from the shipped image for "mainline-like" purity and kept it as a test-time setting. | `overlay/etc/systemd/system.conf.d/60-watchdog.conf`, `overlay/etc/default/u-boot.bak-20261031` | Yes for unattended runs. **H616's sun4i watchdog maxes at 16 s**, so `RuntimeWatchdogSec` must be <= 16s (e.g. 10s) or systemd fails to arm it. | Test-only drop-in pushed by the harness, or `userpatches/overlay/` behind a profile switch; not in the reproducible image unless the user wants it. |
| Kernel-side hygiene audits they did that are worth repeating for H616: every `supply ... not found`, `Failed to create device link`, regmap "zero-initialized flat cache", missing cooling maps, DDR DVFS -> classified as fix / expected / impossible with the reason and the right layer. | `work/_out/board-hygiene/RESULTS.md` | Method applies 1:1; content is RK3588. | `harness/analysis/` for our dmesg (`board-dump-1.txt` already exists). |

### 2.2 U-Boot 2026.10

| Finding | Source | Applies? | Note |
|---|---|---|---|
| OpenSSL 4 host tools | §1 | yes (done) | widen across `v2026.10*` dirs before an Armbian PR |
| AHCI `READ CAPACITY` off-by-one (Pardini, Armbian `patch/u-boot/v2026.10/general-ata-ahci-read-capacity-must-return-the-last-lba.patch`) and naneng-combphy fix | `patches/u-boot/0001,0002` (they copied them from Armbian with `Link:` headers) | No SATA on H616 | Only as a reminder that Armbian's **generic** `general-*.patch` files in `patch/u-boot/v2026.10/` are applied to rockchip64 only, not to sunxi64; nothing there is sunxi-relevant today. |
| Autoboot interrupt: "keep sending CR until `=>` appears; a fixed burst missed the 2 s window once" | `opi5-board-access.md` | yes | Our `scripts/serial-expect.py` should loop CR every ~200 ms until the prompt regex matches, not send a fixed count. |
| `u-boot-menu` + `extlinux.conf` with `fdtdir` and a U-Boot-side `fdtfile` switch | `overlay/etc/default/u-boot`, build-uboot.sh PREBOOT | No (Armbian boot.scr/armbianEnv.txt) | Skip. |

### 2.3 Ubuntu 26.10 userspace quirks seen on real boots

From `work/_out/boot-failures/RESULTS.md`, `work/_out/upstream-check/RESULTS.md`,
`work/_out/desktop-image/RESULTS.md`, `HANDOFF.md`:

| Quirk | Detail | Relevance to our server/print image |
|---|---|---|
| **`systemd-networkd-wait-online` 2 min stall** | netplan matched every `en*`, including a USB NIC with no cable -> `wait-online` held boot for 2 min 10 s. Fix: required NICs explicit, others `optional: true` (`cidata/network-config`). | **High.** Zero2 has eth + uwe5622 Wi-Fi. First-boot check: `systemd-analyze blame | head`, `networkctl`; if wait-online is near its timeout, mark the non-primary link optional in our netplan/networkd config (Armbian `NETWORKING_STACK`). |
| dbus-broker default | `dbus-daemon-launch-helper` absent (our `794f1d4`); malcontent "Invalid user name" (LP #2169483) is desktop-only. | Confirms our fix; nothing else for server. |
| fake-hwclock / no RTC battery | `hwclock: unable to read the hardware clock`; time wrong until NTP. | Zero2's H616 RTC also loses time without power. Armbian stonking packages already include `fake-hwclock`; verify it runs and `timedatectl` syncs. |
| Package renames in 26.10 | `libcec6 -> libcec7`; Qt6 libs dropped the `t64` suffix; **26.10's dpkg rejects two names in a `Maintainer:` field** (jellyfin-desktop `debian/control` failed to parse). | Only if we build/repack any .deb locally (e.g. printer drivers): single Maintainer, check Depends against stonking names. |
| dracut vs initramfs-tools | Ubuntu 26.10 Desktop defaults to dracut; server/Armbian use initramfs-tools. | Our `config/cli/stonking/main/packages` has `initramfs-tools`; make sure no desktop/print metapackage drags `dracut` in (it would take over `/boot/initrd.img-*` generation). |
| Desktop-only noise (skip unless we add a desktop) | geoclue 90 s start timeout (libproxy GIO deadlock), `sssd-*.socket` dependency failures (pulled by `libpam-sss` Recommends), `fwupd-refresh` exit 1 (LP #2170226, fixed in 2.1.6-3ubuntu4), `ubuntu-insights` mount-namespace failures, `85-brltty.rules:611`. | Low. Useful as a "known 26.10 bugs" list when reading `journalctl -p err -b`. |
| Snaps can't be seeded into a chroot | firefox/thunderbird debs are snap installers. | Irrelevant for server. |
| Build speedups under qemu | `--dpkgopt=force-unsafe-io`, man-db auto-update disabled during the build and re-enabled at the end. | Armbian already uses force-unsafe-io; man-db trick is optional. |

---

## 3. Test-harness practices to mirror (concrete)

What we already have: `scripts/board-power.py` (byte-identical to theirs except docstring; UUID
guard present), `scripts/serial-log.py` (pyserial, auto-reconnect, wall-clock stamps),
`scripts/serial-expect.py`, `harness/ssh.sh`, `harness/99-opiz2-serial.rules`
(`/dev/ttyOPIZ2`), `harness/06-opiz2-*.network` (DHCP server + NAT), `flash-sd.sh`.

### 3.1 Immediate fixes to our existing scripts
1. **`scripts/serial-log.py` and `serial-expect.py` default to `/dev/ttyUSB1`.** Both CP2102s
   report serial "0001"; ttyUSB numbering flips on replug. Default `OPIZ2_TTY` to
   `/dev/ttyOPIZ2` (our udev symlink) or the by-path name, as opi5 does
   (`opi5-board-access.md` 2026-11-01 note; their `serial-log.py` defaults to
   `/dev/serial/by-path/pci-0000:00:14.0-usb-0:3:1.0-port0`).
2. **`serial-expect.py`**: loop the CR send for U-Boot prompt capture (see §2.2).
3. `local.env` for our plug must carry `MEROSS_DEVICE` + `MEROSS_UUID` of *our* plug; the
   script refuses otherwise. Rule carried from `opi5-board-power-plug.md`: cycle only when both
   ssh and serial are dead; prefer `systemctl poweroff` + `cycle`; measure our cold-boot-to-ssh
   time once (theirs: `cycle 5` -> up in ~36 s) and use it as the `waitup` budget.

### 3.2 Patterns to copy (with their reference files)
| Practice | Reference | What to build for Zero2 |
|---|---|---|
| **Stall watchdog on every long unattended run**: background waiter fires on completion *and* when the log mtime stalls ~15 min; wait on a PID (`tail --pid=N -f /dev/null`) or `pgrep -x`, never `pgrep -f`/`pkill -f` with a pattern that appears in the waiter's own command line; anchored patterns (`^bash /full/path/x.sh`). Never quote an ETA without checking the driver is alive and the log advancing. | `feedback-watch-unattended-runs.md` | `harness/wait-run.sh <pid> <logfile> [stall-min]` used by every build/test launcher. |
| **Detached board jobs** via `systemd-run --unit=<name> --property=Type=oneshot ...` so they survive ssh drops; progress by `systemctl list-units '<name>-*'`; a `summary.txt` with one line per step and a final sentinel (`DONE`, `cycle k: OK`); host tails it. | `work/_out/usb-resume/board/usbres.sh` (`detached()`), `work/_out/queue/queue.sh`, `deep-suspend/host/run.sh` | `harness/board-run.sh <unit> '<cmd>'` + `harness/board-status.sh`. |
| **Resumable result tables**: `results.tsv` one row per case; rerun skips finished rows; a case that was running when the board died is recorded `FAIL "case never finished"` so a crash is a result, not a loop; `--fresh`, `--summary`, `--list`. | `work/_out/testmatrix/README.md` | Same shape for our feature matrix (Wi-Fi/BT/USB/HDMI/GPIO/thermal). |
| **Copy results off the board immediately** after each run (`rsync` to a host run dir), before reporting. 1.8 GB of results were lost to an SD reflash. | `feedback-copy-results-off-board.md` | `harness/results/<date>-<run>/`; make the waiter do the rsync on completion. |
| **Post-flash boot-health check** (host-driven, unattended): wait for ssh with a budget; then `uname -v`, `systemctl is-system-running`, `/proc/cmdline`, BTF/module-rejection count, expected modules present via `modinfo -n`, device nodes, DRM connector status, `dmesg --level=err,crit,alert,emerg`, DT `__symbols__` present, network throughput; on failure dump the serial tail into the report and print the rescue recipe. | `work/_out/k3-validation/run-k3.sh` (§0-2) | `harness/verify-board.sh` producing `harness/results/<run>/REPORT.md`. Zero2 list: uwe5622 `wlan0` scan+connect, `hci0`, `end0` iperf3 both ways, `lsusb -t` per port, HDMI `card*-HDMI-A-1/status` + `modetest`, HDMI audio `aplay`, thermal zones, `cpufreq` OPP sweep, RTC, SPI NOR `/dev/mtd0` read, GPIO/I2C/SPI headers, LEDs, reboot/poweroff timing, watchdog. |
| **Drop-in module testing** instead of reflashing: `/lib/modules/$(uname -r)/updates/<topic>/*.ko` + `depmod` (+ `update-initramfs -u` if the module is in the initrd, then `lsinitramfs` to prove it), with a CRC guard `modprobe --dump-modversions` old vs new against the running kernel. Remove every `updates/<topic>` when the next kernel deb lands. | `usbres.sh check/install/undo`, `opi5-board-deployed-state.md` | `harness/dropin.sh check|install|undo <ko>`. Pairs with the BTF rule: drop-ins have no BTF and are fine; a bare `Image` is not. |
| **Keep a known-good fallback** before each kernel install: copy `vmlinuz`/`initrd`/DTB to `/var/tmp/*.kN`, keep the previous deb set on the host (`out/debs-k8/`), document the U-Boot rescue command line. | `opi5-board-deployed-state.md`, `HANDOFF.md` | For Armbian: keep `output/debs/` per build numbered; document `armbianEnv.txt` + `boot.scr` manual boot of the old `Image`. |
| **Baseline before fix**: every test script has `baseline` (stock) and `run` (fixed) modes and records both; A/B via `tools/ab.sh on|off` moving a drop-in aside. | `usbres.sh`, `hdmi-10bpc/tools/ab.sh` | Same for any driver fix we test. |
| **External observation**: webcam classifier for display output (GOOD/BLACK/FLAT/SCRAMBLED/WRONGCASE with a per-case code grid), TV input forced over CEC before every display run, verified by camera, never assumed. | `testmatrix/lib/camcheck.py`, `testmatrix/lib/tv-input.sh`, `feedback-tv-input-cec.md` | Optional for Zero2 HDMI; at minimum read `/sys/class/drm/*/status`, `modetest -c` EDID, and `dmesg` per connector. |
| **Serial log with time since start** (gaps in boot visible) and a file header per attach. | `scripts/serial-log.py` | Optional: add a `--relative` mode to ours. |
| **Lab network**: a dedicated host NIC with networkd DHCP server + static lease by MAC + NAT, `ConfigureWithoutCarrier=yes`; board set to `dhcp-identifier: mac` so the lease survives OS reinstalls; IPv6 link-local as the fallback path (`fe80::...%<if>`). | `scripts/nat-on.sh`, `make-board-permanent.sh`, `opi5-board-deployed-state.md` 2026-10-31 | Add `[DHCPServerStaticLease]` for the Zero2 MAC to `harness/06-opiz2-*.network` so `harness/ssh.sh`'s `10.56.0.107` stays valid across reflashes; make the image's netplan use `dhcp-identifier: mac`. |
| **Secrets and site values** out of scripts: `local.env` (chmod 600, git-ignored) for plug key, board address, credentials; `cidata/user-data` never published; `tools/secret-scan.sh` refuses to publish keys, `*.ko`, `*.dtb`, `*.img`, `known_hosts`, non-owner e-mails outside patches. | `~/orangepi5-github/tools/secret-scan.sh`, `CONTRIBUTING.md` | Our `harness/id_ed25519*`, `known_hosts`, `local.env` must stay out of anything we publish; copy the scan if we publish the harness. |
| **Host hygiene**: `cleanup-build-space.sh` deletes only regenerable build output, refuses dirs in use (`/proc/*/cwd`, cmdline), git worktrees with changes, anything touched in the last 30 min; prints a plan and asks. | `scripts/cleanup-build-space.sh` | Useful template once `armbian-build/cache` and `output` grow. |

### 3.3 Working-practice rules from their feedback memory that bite on any board project
- Root-cause, upstreamable fix in the right layer; a board-DTS `status = "disabled"` is a
  diagnostic, never the fix (`feedback-proper-fix.md`). Robustness (repeated start/stop, SIGKILL
  mid-stream, hot-unplug) is part of "working".
- Port series whole; before calling a DT/companion patch "optional", prove the code path runs
  (`devm_*_get_optional()` returning NULL silently no-ops a driver fix) (`feedback-port-whole-series.md`).
- Before debugging something new, check existing sources (Armbian patch dirs, megous tree,
  lore) for a fix; they ran a full external-source audit (`work/_out/patch-audit/REPORT.md`) with
  an `apply-check.sh` (temporary index, no worktree) per candidate.
- When bundling or replacing work, kill the superseded builds/agents in the same step
  (`feedback-stop-superseded-work.md`).
- Coordination files: `work/BRIEF.md` (rules for every agent: worktree per topic, `-j` cap, no
  upstream sending, where artifacts go), `work/_out/HANDOFF.md` (running log), `FIXLIST.md`
  (numbered open items), `BOARD-QUEUE.md` (serialized board use: one installer/rebooter at a
  time; nothing needing a manual power cycle while the user is away), `RESULTS.md` per topic.
- Downloads (mboxes, vendor code) live in `_downloads/<item>/`, are untrusted, and Python that
  reads them runs with `python3 -I`.

---

## 4. Their Armbian contribution workflow, and what is actually in it

Honest summary: **no Armbian PR, issue or fork exists yet.** What exists is an audit and a set
of conventions observed while reading Armbian's tree, plus the general patch-hygiene rules they
hold themselves to. Concretely:

### 4.1 What they recorded about Armbian (from `opi5-armbian-contrib.md`, `work/_out/armbian/REPORT.md`)
- Branch -> kernel map at `fb22cb0`: `vendor` = BSP 6.1/6.12 (`rk35xx-vendor-*`), `current`
  = 6.18 (`archive/rockchip64-6.18`, 209 patches), `edge` = 7.3 (`archive/rockchip64-7.3`,
  269 patches, all apply on v7.3.1), `bleedingedge` = 7.4 (no dir yet). Board conf
  `config/boards/<board>.conf` with a maintainer; mainline U-Boot pinned per family
  (`BOOTBRANCH=tag:v2026.xx`, `BOOTPATCHDIR=v2026.xx-<family>`).
- Armbian patch headers: proper `From:`/`Subject:`/body/`Signed-off-by:`; Armbian maintainers
  themselves use `Assisted-by: Claude Opus 5.5` (Pardini's combphy and AHCI patches), so an AI
  trailer is accepted there. File naming seen: `general-<subsystem>-<what>.patch` for
  SoC-generic, `board-<board>-<what>.patch` for one board, `<soc>-NNNN-<what>.patch` /
  `media-NNNN-*.patch` for series, `dw-wdt-N`, debug patches kept but named as such.
- Their triage taxonomy for Armbian patches is the reusable part: *taken (author kept, Link:
  to the Armbian blob URL added)* / *already ours* / *rejected: debug only, vendor-ism,
  Chromium workaround, policy change, unproven by its own author, other board/SoC, not
  mainline-like (overlay framework)* / *needs user (behavioural change without a symptom)*.
- Overlaps they would drop before contributing to Armbian: anything Armbian already carries
  (VP9 VDPU381, panthor clk), and where Armbian solved the same thing differently (big-core
  clocks via SCMI clk driver vs their DT assigned-clocks).

### 4.2 Armbian conventions as they stand in **our** tree (what a PR to sunxi must respect)
These come from reading `armbian-build` itself, not from opi5; listed here so the Zero2 work has
them in one place.
- Kernel: `patch/kernel/archive/sunxi-7.3/series.conf` (729 lines, tab-indented paths, a
  leading `-` disables a patch without deleting it; subdirs `patches.megous/`,
  `patches.armbian/`, `patches.backports/`, `patches.drm/`, `patches.media/`; header cites the
  source tree, megi's `orange-pi-7.3`). `0000.patching_config.yaml`: bare `.dts` in `dt_64/`
  are copied to `arch/arm64/boot/dts/allwinner`, bare overlays in `overlay_64/` to
  `.../allwinner/overlay`, and **the DT Makefiles are auto-patched** (`auto-patch-dt-makefile`,
  `add-only`) so patches must not touch `arch/arm64/boot/dts/allwinner/Makefile`; the
  patches-to-git dev cycle also refuses to commit `MAINTAINERS` and
  `Documentation/devicetree/bindings/arm/allwinner.yaml` churn. New board DTS = drop the file
  in `dt_64/`, no Makefile patch.
- U-Boot sunxi64: `patch/u-boot/v2026.10-sunxi64/` flat `*.patch` applied in name order
  (`zz-` prefix sorts last), `board_<board>/` subdirs (26 boards) for board-only patches, a
  `README.md` that documents the baseline move and the policy "start from a clean upstream
  baseline and re-add only the patches still needed, board by board, as CI / on-target boot
  tests confirm them". The rockchip `v2026.10/` dir additionally uses
  `0000.patching_config.yaml` `overlay-directories` (`defconfig/`, `dt_uboot/`,
  `dt_upstream_rockchip/`).
- Framework code fixes (our `lib/functions/*` commits) are what Armbian would want as PRs
  with the upstream-bug reasoning in the message (OpenSSL 4, uutils `ln`, dbus-broker,
  base-files json). Our commit messages currently carry `Co-Authored-By: Claude ...` and
  `Claude-Session:` trailers (required by this harness); opi5's rule is a single
  `Assisted-by: Claude:<model>` trailer + the user's `Signed-off-by` last, no
  `Co-Authored-By` (`feedback-ai-attribution.md`). **User decision** which style the Armbian
  PRs carry; whichever it is, the PR body should say how the change was tested (which host
  release, which board boot).
- Gating they apply to anything sent anywhere: only after the hardware test passes; the user
  sends; nothing else contacts upstream (`BRIEF.md` "Don't send anything upstream").

### 4.3 Their upstream-staging structure (model for publishing our patches)
`~/orangepi5-github` (public repo `SomeComputerGuy/orangepi5-mainline`, commits `d6e6143`,
`e8a9751`, `990101a`): one directory per kernel topic `topics/<topic>/{ours,carried,local}/`
+ `series` + `topic.env` + generated `README.md` (table of patches, author, lore Link) +
`notes/` (RESULTS.md, TESTING.md) + `cover-letter.draft.txt`; `STATUS.md` generated from
`tools/export/topics.conf` (`name | branch | parent | out | title | hw-tested | next-step`);
`tests/<name>/` exported from `tests.conf` with lab values made overridable; patches
classified automatically (local if the subject says DO NOT UPSTREAM/DEBUG, ours if the author
is the owner, else carried, kept byte-for-byte with authorship and `Link:`). A smaller version
of this (topic dirs with `ours/`, `notes/TESTING.md`, `STATUS.md`) is the right shape for our
`userpatches/` additions once there are more than a handful.

---

## 5. Explicitly not carried (RK3588-only)
TF-A/rkbin/DDR blob, 24 MHz big-core fix, M.2 SATA/NVMe auto-detect, SMMU-v3 power domain,
all rkvdec/hantro/VOP2/HDMI-FRL/DP work, Ubuntu-config kernel + arm64 sysroot for
cross-built headers, the media .deb rebuilds and in-image signed apt repo, cloud-init NoCloud
CIDATA partition layout, `u-boot-menu`/extlinux boot.

---

## 6. Prioritized action list (destination in our tree)

1. **Fix harness defaults**: `scripts/serial-log.py`, `scripts/serial-expect.py` -> default
   `/dev/ttyOPIZ2`; CR loop until the U-Boot prompt; static DHCP lease for the Zero2 MAC in
   `harness/06-opiz2-*.network`.
2. **Write `harness/verify-board.sh`** (post-flash health + feature checks, report to
   `harness/results/<run>/REPORT.md`) and **`harness/wait-run.sh`** (completion + stall
   watchdog, PID-based). Both pattern-copied from `k3-validation/run-k3.sh` and the
   `feedback-watch-unattended-runs.md` rules.
3. **First-boot check for `systemd-networkd-wait-online`** stalls with Wi-Fi/eth unplugged;
   fix in our netplan/networkd config in `userpatches/` (not on the board).
4. **Add a rootless `mmdebstrap --mode=unshare` package-set preflight** (`scripts/`), so
   `packages.additional` changes are validated in minutes.
5. **Widen the OpenSSL-4 U-Boot fix** to every `patch/u-boot/v2026.10*` dir or do it in
   `lib/functions/compilation/uboot.sh` (hooks `pre_config_uboot_target`/`post_config_uboot_target`,
   `scripts/config --disable TOOLS_LIBCRYPTO` fallback as opi5 does) before proposing it to
   Armbian; cite upstream U-Boot status in the header.
6. **Candidate kernel backports for sunxi-7.3** when we touch suspend: `4785d5faa935`
   (s2idle begin/end) and `33392343c74e` (DPM watchdog, test kernels only), via
   `patch/kernel/archive/sunxi-7.3/patches.armbian/` + `series.conf`.
7. **Board-test rules file** (`harness/RULES.md`): whole-deb kernel installs only (BTF),
   drop-in modules with CRC check, fallback kernel kept, results rsynced off-board after every
   run, power-cycle only when ssh and serial are both dead, 16 s watchdog ceiling on H616,
   known-benign dmesg lines.
8. **Decide the AI-attribution style for Armbian PRs** (user) and whether to keep
   `Co-Authored-By` or switch to `Assisted-by:` + SoB; then prepare the framework commits
   (`ef99c0c`, `971dd01`, `794f1d4`, `9ff4ce3`, widened `f318c9c`) as one PR with host-release
   test notes.
