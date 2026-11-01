# Orange Pi Zero2 (Allwinner H616) — mainline Armbian bring-up and print server

Reproducible Armbian image for the Orange Pi Zero2: Ubuntu 26.10 ("stonking") userspace,
mainline Linux 7.3.x (Armbian `edge`), U-Boot 2026.10, CUPS with broad printer-driver coverage.
Goal: every piece of board hardware working with zero known bugs; all fixes upstreamable.

- Armbian framework fork + branches: https://github.com/SomeComputerGuy/build (integration branch `stonking-orangepizero2`; one `fix/*` or `feat/*` branch per upstream PR).
- `userpatches/` — Armbian build profile (`./compile.sh opiz2-printserver`); copy into the framework checkout's `userpatches/`.
- `kernel-check/build-kernel.sh` — rootless patch-apply + kernel compile check mirroring Armbian's sunxi-7.3 patch set.
- `flash-sd.sh` — guarded SD-card flasher.
- `scripts/` — test-harness tooling: `board-power.py` (Meross plug, UUID-guarded), `serial-log.py`, `serial-expect.py`.
- `harness/` — host-side harness config (networkd/udev files, `ssh.sh`), board analysis dumps and research reports.
- `docs/` — status and plans.

Build: clone armbian/build (or the fork above, branch `stonking-orangepizero2`), copy `userpatches/` in, run `./compile.sh opiz2-printserver` as a normal user (it sudo's itself).

License: GPL-2.0-only for scripts and docs in this repo. Commits carry `Assisted-by:` per the kernel's coding-assistants process.
