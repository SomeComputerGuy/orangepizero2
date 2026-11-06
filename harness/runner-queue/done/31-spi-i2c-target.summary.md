# 31-spi-i2c-target: FAIL (3 FAIL, 2 ROUND-DONE)
Kernel c27 (uname -v #25 SMP PREEMPT Fri Nov  6 04:18:02 UTC 2026). Start 05:00:10, end 05:05:06. rc 0. ROUND-DONE count 2: PASS. CHECK FAIL count 3: FAIL.
```
WIRED_SPI=0
WIRED_I2C=0
kernel: 7.3.1 #25 SMP PREEMPT Fri Nov  6 04:18:02 UTC 2026
overlays: user_overlays=sit-spi1-target sit-spi-gpio-pc 
INFO wired: SPI=0
CHECK W33-spi-target-probe PASS spi1 registered as a target, slave='spi-dev', 0 error lines
CHECK W33-spi-target-spidev PASS /dev/spidev1.0 at boot from the overlay slave child (spidev)
CHECK W33-spi-target-abort PASS blocked transfer ended on SIGINT in 3s (rc 124)
CHECK W33-spi-loopback-16 SKIP NOT TESTED: no jumpers pin 13 PC5->23 PH6, 11 PC6->19 PH7, 22 PC7<-21 PH8, 15 PC8->3 PH5 detected
CHECK W33-spi-target-unregister PASS spidev1.0 removed
CHECK W33-spi-target-reregister PASS /dev/spidev1.0 back after 'echo spi-dev > slave' (slave='spi-dev')
INFO spi-gpio host: spi2
INFO dmesg spi: [   44.071975] spidev spi1.0: 8 bits per word|[   44.071994] spidev spi1.0: setup mode 0, 8 bits/w, 500000 Hz max --> 0|[   44.072002] spidev spi1.0: 500000 Hz (max)|[   46.921891] spidev spi1.0: SPI transfer failed: -4|[   46.921946] spi_slave spi1: failed to transfer one message from queue|[   46.921962] spi_slave spi1: noqueue transfer failed|[   48.387147] spi spi1.0: setup mode 0, 8 bits/w, 100000000 Hz max --> 0|[   48.387982] sun6i-spi 5011000.spi: registered child spi1.0|
INFO dmesg-warn: [    0.245330] WARNING: drivers/media/mc/mc-device.c:619 at media_device_register_entity+0x194/0x1c0, CPU#3: swapper/0/1
INFO dmesg-warn: [    0.245615] Call trace:
INFO dmesg-warn: [    0.245973] WARNING: drivers/media/mc/mc-device.c:619 at media_device_register_entity+0x194/0x1c0, CPU#3: swapper/0/1
INFO dmesg-warn: [    0.246246] Call trace:
kernel: 7.3.1 #25 SMP PREEMPT Fri Nov  6 04:18:02 UTC 2026
overlays: user_overlays=sit-i2c3-slave sit-i2c2-ph 
INFO wired: I2C=0
CHECK W33-i2c-target-func FAIL no /dev/i2c-3 (i2c3 did not probe with the sit-i2c3-slave overlay)
INFO evidence 5002c00: dmesg: 
INFO evidence 5002c00: dt status: okay overlays-applied: symbols-present
INFO evidence 5002c00: devices_deferred: 
CHECK W33-i2c-slave-eeprom-bind FAIL no /sys/bus/i2c/devices/3-1064
CHECK W33-i2c-host-with-target FAIL i2cdetect -y -r 3 rc 1 in 0s: Error: Could not open file `/dev/i2c-3' or `/dev/i2c/3': No such file or directory
INFO i2cdetect 3 found: 
CHECK W33-i2c-loopback-16 SKIP NOT TESTED: no jumpers pin 5 PH4<->pin 8 PH2, pin 3 PH5<->pin 10 PH3 detected
INFO dmesg i2c: [    0.235110] i2c_dev: i2c /dev entries driver|[    0.320950] sun50i-h616-r-pinctrl 7022000.pinctrl: initialized sunXi PIO driver|[    0.335572] sun50i-h616-r-pinctrl 7022000.pinctrl: supply vcc-pl not found, using dummy regulator|[    0.349660] sun50i-h616-pinctrl 300b000.pinctrl: initialized sunXi PIO driver|
INFO dmesg-warn: [    0.245973] WARNING: drivers/media/mc/mc-device.c:619 at media_device_register_entity+0x194/0x1c0, CPU#1: swapper/0/1
INFO dmesg-warn: [    0.246256] Call trace:
INFO dmesg-warn: [    0.246609] WARNING: drivers/media/mc/mc-device.c:619 at media_device_register_entity+0x194/0x1c0, CPU#1: swapper/0/1
INFO dmesg-warn: [    0.246879] Call trace:

dmesg Oops/BUG/WARNING/Call trace/timed out/already requested lines:
[    0.245973] WARNING: drivers/media/mc/mc-device.c:619 at media_device_register_entity+0x194/0x1c0, CPU#1: swapper/0/1
[    0.246256] Call trace:
[    0.246609] WARNING: drivers/media/mc/mc-device.c:619 at media_device_register_entity+0x194/0x1c0, CPU#1: swapper/0/1
[    0.246879] Call trace:
[    0.245330] WARNING: drivers/media/mc/mc-device.c:619 at media_device_register_entity+0x194/0x1c0, CPU#3: swapper/0/1
[    0.245615] Call trace:
[    0.245973] WARNING: drivers/media/mc/mc-device.c:619 at media_device_register_entity+0x194/0x1c0, CPU#3: swapper/0/1
[    0.246246] Call trace:

2026-11-06 05:05:06 restored: #17 SMP PREEMPT Fri Oct 30 12:09:52 UTC 2026 vmlinuz-7.3.1-edge-sunxi64 sun50i-h616-orangepi-zero2.dtb.stock 0 
```
Restored line shows vmlinuz-7.3.1-edge-sunxi64, dtb .stock, 0 overlays: PASS. Results: harness/research/spi-i2c-target/logs/runner/
