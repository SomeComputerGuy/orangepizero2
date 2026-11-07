# Reflash the board's SD card over netboot (runner instructions)

This is a mechanical procedure. The coordinator hands it to the board runner (a cheap model) when an image needs flashing.
Follow it exactly. Do not edit any script and make no judgement calls; if something here doesn't cover what happens, stop and report "package not ready: <what>".
The global rules (~/.claude/CLAUDE.md) and harness/AGENT-RULES.md come first.

No sudo is needed. The host's dnsmasq TFTP server (/etc/dnsmasq.d/opiz2-tftp.conf, root /srv/tftp/opiz2) is already
set up and running; netboot-setup.sh was done once on 2026-11-03.
How it works: the board pxe-boots a BusyBox flasher, which pulls the image over HTTP from 10.56.0.1:8080, writes /dev/mmcblk0,
verifies the sha256 and reboots. reflash.sh then runs the first-login wizard over serial, installs the ssh key, sets the timezone and
runs verify-board.sh.

- Type: DEV (it takes the whole board). Expected duration: 20-40 min.
- Never touch /dev/ttyUSB0, enp130s0, or the Meross plug 192.168.107.245.
- Never print or `source` local.env.
- Power cycling: only `--power-cycle`, and only when ssh AND serial are both dead.

## Inputs (from the coordinator's job message)
- IMAGE: which variant to flash. Default: server. The images are in armbian-build/output/images/:
  - server:  `Armbian-unofficial_26.11.0-trunk_Orangepizero2_stonking_edge_<kver>.img.xz` (newest; <kver> = the image's
    kernel, 7.3.3 since the 2026-11-07 build, 7.3.1 before)
  - minimal: `..._<kver>_minimal.img.xz`, desktop: `..._<kver>_desktop.img.xz`
- TAG: the label for the log directory (for example the armbian-build commit, `git -C armbian-build log -1 --format=%h`).

## Steps
Run everything from /home/aruni/orangepizero2. `I=armbian-build/output/images/<IMAGE file>`; L=harness/queue/reflash-<TAG>.

1. Preconditions (stop with BLOCKED if any fails):
   - `ls -l $I $I.sha` both exist, and the image is newer than the coordinator's "build finished" time if one was given;
   - `harness/board-lock.sh status` shows no holder (otherwise acquire waits; never break a lock);
   - `mkdir -p $L`.
2. `harness/board-lock.sh acquire reflash-runner 3600`
3. Dry run: `harness/reflash.sh --dry-run --image $I 2>&1 | tee $L/dryrun.log`
   - PASS = it ends with `dry run complete`, and the log contains `identical` for every tftp fetch, `manifest served ok`
     and `image served ok`.
   - Otherwise release the lock and report BLOCKED with the failing lines.
4. Real run, in the background, with one completion wait (no polling more often than every 10 min):
   `harness/reflash.sh --image $I > $L/reflash.log 2>&1; echo "rc=$?" >> $L/reflash.log`
5. If step 4 failed:
   - **Only the first-login step or a later one failed** (the log shows `FLASHER: RESULT OK`, then `first-login automation failed`
     or `key/timezone setup failed`):
     run `harness/reflash.sh --post-only > $L/reflash-post.log 2>&1` once.
   - **The flasher step failed** (`flasher failed` / `U-Boot pxe step failed`): re-run step 4 ONCE (U-Boot on SPI NOR is
     untouched, so a re-run is safe). If it fails again, stop and report BLOCKED.
   - Anything else: stop and report BLOCKED with the last 30 lines of the log.
6. `harness/board-lock.sh release reflash-runner` (always, also on BLOCKED).

## Pass/fail (mechanical)
1. `grep -c 'FLASHER: RESULT OK' $L/reflash*.log` >= 1, or the log has "sha256 ... OK" from the flasher.
2. The log has `ssh ok:`; write down the kernel string from that line.
3. verify-board.sh: count `^FAIL` lines in $L/reflash*.log; it must be 0. Write down the PASS count and every FAIL line exactly.
4. `grep -n -i -E 'oops|BUG:|panic' $L/reflash*.log` has no hits.
5. The last line is `rc=0` (or the --post-only run ended rc 0).

## Summary (harness/runner-queue/done/<NN>-reflash.summary.md)
It must list:
- the image file and its sha256 line;
- the TAG and the start/end times;
- each check above with its PASS/FAIL value;
- the PASS count and any FAIL lines of verify-board.sh;
- the kernel from `ssh ok:`;
- the log paths.

Commit only the summary and the text logs in $L (`git commit -- <paths>`, author Arun Iyengar <aiyengar1990@gmail.com>, no
Co-Authored-By), then push origin main. Report once to the coordinator.

After a reflash the board runs the new image's stock kernel. Any later trial-kernel job installs its own kernel as usual.
