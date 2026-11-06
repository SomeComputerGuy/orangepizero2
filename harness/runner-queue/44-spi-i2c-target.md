# Job 44-spi-i2c-target (DEV, ~12 min incl. three reboots) = job 43 rerun (I2C set mandatory, then SPI sanity)
Package: harness/research/spi-i2c-target/runner/ (script sit-job.sh, board-sit.sh, *.py, HANDOFF.md).
Command: `bash harness/research/spi-i2c-target/runner/sit-job.sh`
Why again: job 43 (c36) everything PASS except W33-i2c-slave-eeprom-bind (client 3-1064 present, no driver). Root cause:
the DT client's uevent is an of: modalias and i2c-slave-eeprom (=m) only had i2c: aliases, so it never autoloaded. Fix:
armbian-build b7b01b931 (fix/sunxi-i2c-slave-eeprom-of-autoload, OF match table), merged in test-cumulative 1e1fd3eae
= c37. c37 is a module-only change: Image md5 = c36's and `uname -v` says #36 (expected). The package now also prints
every jumper item as its own SKIP line (job 43 printed only the first of each set).
Order: chunk `i2c` first (mandatory), then chunk `spi` (short sanity, about 1 min of checks).
Kernel: the newest cumulative kernel (c37 or later); it must contain 03961fad0, 85e6dcb38, c6ce58c59 and b7b01b931, its
DTB the i2c3 alias and its modules.alias the of: alias of i2c_slave_eeprom. Otherwise the script exits 2 + BLOCKED:
report "not ready", not FAIL.
Watchdog/timeouts: board-sit.sh under `timeout 600` per set, stall watchdog 300 s; lock, resume (logs/runner/state) and
restore to the stock kernel are in the script.
Jumpers optional: without them the loopback items are SKIP = NOT TESTED (never FAIL).
Checks: HANDOFF.md "Checks" (mechanical: 2 ROUND-DONE, exactly 15 `CHECK` lines listed verbatim, 0 FAIL overall,
`INFO adapters:` / `INFO 5002c00.i2c driver:` / `INFO evidence` / `INFO eeprom evidence:` lines verbatim, `restored:`
line with the stock kernel, the .stock DTB and 0 overlays).
Results: harness/research/spi-i2c-target/logs/runner/ (job 43's are in logs/job43/). Submitted 2026-11-06 by the W33 agent.
