# Job 43-spi-i2c-target summary
Start 2026-11-06 09:57:03, end 10:01:48. Kernel: 7.3.1 #36 SMP PREEMPT Fri Nov 6 09:44:09 UTC 2026 (c36). Exit 0, no BLOCKED. ROUND-DONE count 2 (PASS). CHECK FAIL count 1 (overall FAIL).
Results: harness/research/spi-i2c-target/logs/runner/
```
WIRED_SPI=0
WIRED_I2C=0
kernel: 7.3.1 #36 SMP PREEMPT Fri Nov  6 09:44:09 UTC 2026
overlays: user_overlays=sit-spi1-target sit-spi-gpio-pc 
INFO wired: SPI=0
CHECK W33-spi-target-probe PASS spi1 registered as a target, slave='spi-dev', 0 error lines
CHECK W33-spi-target-spidev PASS /dev/spidev1.0 at boot from the overlay slave child (spidev)
CHECK W33-spi-target-abort PASS blocked transfer ended on SIGINT in 3s (rc 124)
CHECK W33-spi-loopback-16 SKIP NOT TESTED: no jumpers pin 13 PC5->23 PH6, 11 PC6->19 PH7, 22 PC7<-21 PH8, 15 PC8->3 PH5 detected
CHECK W33-spi-target-unregister PASS spidev1.0 removed
CHECK W33-spi-target-reregister PASS /dev/spidev1.0 back after 'echo spi-dev > slave' (slave='spi-dev')
INFO spi-gpio host: spi2
INFO dmesg spi: [   42.548766] spidev spi1.0: 8 bits per word|[   42.548783] spidev spi1.0: setup mode 0, 8 bits/w, 500000 Hz max --> 0|[   42.548791] spidev spi1.0: 500000 Hz (max)|[   45.397986] spidev spi1.0: SPI transfer failed: -4|[   45.398040] spi_slave spi1: failed to transfer one message from queue|[   45.398056] spi_slave spi1: noqueue transfer failed|[   46.872025] spi spi1.0: setup mode 0, 8 bits/w, 100000000 Hz max --> 0|[   46.872623] sun6i-spi 5011000.spi: registered child spi1.0|
kernel: 7.3.1 #36 SMP PREEMPT Fri Nov  6 09:44:09 UTC 2026
overlays: user_overlays=sit-i2c3-slave sit-i2c2-ph 
INFO wired: I2C=0
INFO adapters: i2c-2=mv64xxx_i2c adapter i2c-3=mv64xxx_i2c adapter i2c-6=DesignWare HDMI 
INFO 5002c00.i2c driver: mv64xxx_i2c bus: 3; 5002800.i2c bus: 2
CHECK W33-i2c-bus-number PASS TWI3 5002c00 = i2c-3, TWI2 5002800 = i2c-2 (i2c aliases)
CHECK W33-i2c-target-func PASS i2c-3 funcs 0xeff002b has I2C_FUNC_SLAVE
CHECK W33-i2c-slave-eeprom-bind FAIL 3-1064 driver='' slave-eeprom size='' (reg_target failed?)
CHECK W33-i2c-host-with-target PASS i2cdetect -y -r 3 rc 0 in 0s
INFO i2cdetect 3 found: 
CHECK W33-i2c-loopback-16 SKIP NOT TESTED: no jumpers pin 5 PH4<->pin 8 PH2, pin 3 PH5<->pin 10 PH3 detected
INFO dmesg i2c: [    0.238211] i2c_dev: i2c /dev entries driver|[    0.324049] sun50i-h616-r-pinctrl 7022000.pinctrl: initialized sunXi PIO driver|[    0.338961] sun50i-h616-r-pinctrl 7022000.pinctrl: supply vcc-pl not found, using dummy regulator|[    0.353112] sun50i-h616-pinctrl 300b000.pinctrl: initialized sunXi PIO driver|
2026-11-06 10:01:48 restored: #17 SMP PREEMPT Fri Oct 30 12:09:52 UTC 2026 vmlinuz-7.3.1-edge-sunxi64 sun50i-h616-orangepi-zero2.dtb.stock 0 
```
dmesg lines matching Oops/BUG/WARNING/Call trace/timed out/already requested: none.
Note: dmesg spi shows 'SPI transfer failed: -4' (from the SIGINT abort check, expected).
