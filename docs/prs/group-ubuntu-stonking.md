# Add Ubuntu 26.10 (stonking) as build target and host, with three rootfs fixes it needs

Branch: `pr/group/ubuntu-stonking` (bf78963ad). Fork: SomeComputerGuy/build. Base: armbian/build `main` c2908d2 (2026-11-02). Draft only, not opened.

## What
- `config/distributions/stonking`, `config/cli/stonking` (copies of resolute's lists), Ubuntu detection,
  supported host release, `qemu-user-binfmt` on 26.10 hosts, keyring handling.
- apt-utils: when the GHA json lacks the new release, find the upstream `base-files` in the distro Packages index.
- rootfs: create the `armbian.gpg` symlink on the host, not in the chroot (26.10's uutils `ln -f` needs
  `/dev/urandom`, absent in the early chroot; the rerun on a cached rootfs failed).
- rootfs: skip the dbus `dbus-daemon-launch-helper` chown when the file is absent (26.10 uses dbus-broker).

## Why
26.10 images and 26.10 build hosts did not work at all.

## Testing
Full Orange Pi Zero2 CLI image (sunxi64 edge, Linux 7.3.1) built on an Ubuntu 26.10 host and booted on the board
(docs/status.md, 2026-11-01). The same distro definitions were used for every later image.

## Upstream status
Nothing equivalent in armbian/build main as of c2908d2.

## Notes for the submitter
The first commit's subject still says "and Orange Pi Zero2 print-server build profile"; the profile is not in this
branch (it lives in userpatches). Reword to "Add Ubuntu 26.10 (stonking)" and give the three fix commits a body
(they have none) before opening. Consider also folding `fix/uboot-sunxi64-host-tools-openssl4` in, since it is the
other 26.10-host blocker.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
