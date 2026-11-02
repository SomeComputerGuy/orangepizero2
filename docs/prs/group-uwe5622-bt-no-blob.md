# uwe5622: Bluetooth without the hciattach_opi blob (in-kernel vendor init + btattach)

Branch: `pr/group/uwe5622-bt-no-blob` (996a05c1a). Fork: SomeComputerGuy/build. Base: armbian/build `main` c2908d2 (2026-11-02). Draft only, not opened.

## What (2 commits on top of pr/group/uwe5622)
- sprdbt_tty sends the PSKEY/RF/enable vendor commands itself on rfkill power-on (ported from Reinerost's OpenWrt
  driver); BD address from `bdaddr=`, else sunxi_addr. `vendor_init=0` keeps the old behaviour.
- `aw859a-bt-attach` helper: rfkill unblock, then stock BlueZ `btattach`, or the blob when `vendor_init=0`.
  The blob stays installed as fallback.

## Why
Bluetooth depended on a closed-source x86/arm binary.

## Testing (Orange Pi Zero2)
hci0 up without the blob, BR/EDR + LE scan finds devices (docs/spec-checklist.md). Pairing and LE 5.0 features not
tested yet.

## Upstream status
Driver part to be offered to armbian/uwe5622.

## Depends on
pr/group/uwe5622 (open that first, or open this one as its follow-up).

🤖 Generated with [Claude Code](https://claude.com/claude-code)
