# 20-spi-i2c-target: FAIL (4 CHECK FAIL lines)
Start 2026-11-06 01:23:10 UTC, end 01:27:06 UTC. ROUND-DONE=1. Overall: 4 FAIL. dmesg.txt: no Oops/BUG:/WARNING/Call trace/timed out lines. Jumpers: WIRED_SPI=0 WIRED_I2C=0 (loopback items SKIP = NOT TESTED).
```
INFO wiring: gpiochip1, libgpiod v1
INFO wiring SPI PC5:PH6 follows=0
INFO wiring SPI PC6:PH7 follows=0
INFO wiring SPI PC7:PH8 follows=0
INFO wiring SPI PC8:PH5 follows=0
INFO wiring I2C PH2:PH4 follows=0
INFO wiring I2C PH3:PH5 follows=0
WIRED_SPI=0
WIRED_I2C=0
ROUND-DONE
kernel: 7.3.1 #23 SMP PREEMPT Fri Nov  6 00:46:05 UTC 2026
overlays: user_overlays=sit-spi1-target sit-spi-gpio-pc sit-i2c3-slave sit-i2c2-ph 
INFO wired: SPI=0 I2C=0
CHECK W33-i2c-target-func FAIL no /dev/i2c-3 (i2c3 not enabled by the sit-i2c3-slave overlay?)
CHECK W33-i2c-slave-eeprom-bind FAIL no /sys/bus/i2c/devices/3-1064
CHECK W33-i2c-host-with-target FAIL i2cdetect -y -r 3 rc 1 in 0s: Error: Could not open file `/dev/i2c-3' or `/dev/i2c/3': No such file or directory
INFO i2cdetect 3 found: 
CHECK W33-i2c-loopback-16 SKIP NOT TESTED: no jumpers pin 5 PH4<->pin 8 PH2, pin 3 PH5<->pin 10 PH3 detected
CHECK W33-spi-target-probe PASS spi1 registered as a target, slave='(null)', 0 error lines
CHECK W33-spi-target-spidev FAIL no /dev/spidev1.0: 
INFO spi-gpio host: spi2
INFO dmesg spi/i2c: [    0.385717] spi spi3.0: setup mode 0, 8 bits/w, 40000000 Hz max --> 0|[    1.521468] sun6i-spi 5010000.spi: registered child spi3.0|[    1.522833] sun6i-spi 5011000.spi: registered target spi1|[    1.529853] sun50i-h616-pinctrl 300b000.pinctrl: pin PH5 already requested by 5011000.spi; cannot claim for 5002c00.i2c|[    1.529883] sun50i-h616-pinctrl 300b000.pinctrl: error -EINVAL: pin-229 (5002c00.i2c)|[    1.529909] mv64xxx_i2c 5002c00.i2c: error -EINVAL: Error applying setting, reverse things back|[   38.748184] spi spi1.0: setup mode 0, 8 bits/w, 100000000 Hz max --> 0|[   38.748400] sun6i-spi 5011000.spi: registered child spi1.0|
2026-11-06 01:27:06 restored: #17 SMP PREEMPT Fri Oct 30 12:09:52 UTC 2026 vmlinuz-7.3.1-edge-sunxi64 0 
```
Results: harness/research/spi-i2c-target/logs/runner/
