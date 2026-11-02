# bsp: silence three recurring systemd boot warnings

Branch: `pr/fix/bsp-systemd-boot-warnings` (df0f0fe40). Fork: SomeComputerGuy/build. Base: armbian/build `main` c2908d2 (2026-11-02). Draft only, not opened.

## What
armbian-bsp-cli drop-ins: tmpfiles override for journal NOCOW (armbian-ramlog makes /var/log/journal a symlink),
`EXTRA_OPTS=` for cron.service, `ConfigurationDirectoryMode=0755` for bluetooth.service.

## Why
Three warnings on every boot of every Armbian image with ramlog / cron / bluez.

## Testing
Orange Pi Zero2, Ubuntu 26.10 image: 0 of the three warnings in `journalctl -b` (board PASS).

🤖 Generated with [Claude Code](https://claude.com/claude-code)
