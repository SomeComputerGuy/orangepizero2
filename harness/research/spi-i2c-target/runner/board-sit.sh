#!/bin/bash
# board-sit.sh: mechanical checks for datasheet item W33 (SPI target mode in spi-sun6i, I2C target mode in
# i2c-mv64xxx), runner job 43 (jobs 20/31 reworked). Runs on the Zero2 as root. Three modes:
#   board-sit.sh wiring             on the STOCK kernel, before the overlays: finds out with GPIO whether the
#                                   loopback jumpers are fitted (drives one end, reads the other; both levels
#                                   must follow). Prints WIRED_SPI=0|1 and WIRED_I2C=0|1.
#   board-sit.sh checks-spi <spi>   trial kernel booted with the user overlays sit-spi1-target + sit-spi-gpio-pc.
#   board-sit.sh checks-i2c <i2c>   trial kernel booted with the user overlays sit-i2c3-slave + sit-i2c2-ph.
#   <spi>/<i2c> are the WIRED_* values. The two sets boot separately: spi1-target (CS0) and i2c3 (SDA) both use PH5
#   (header pin 3); in one boot the second one to probe loses the pin (job 20: "pin PH5 already requested by
#   5011000.spi; cannot claim for 5002c00.i2c").
# Output: "CHECK <item> PASS|FAIL|SKIP <value>" lines (SKIP = NOT TESTED, never a failure), INFO lines, ROUND-DONE.
# Needs /root/sit/spi_xfer.py, i2c_loop.py, i2c_funcs.py (python3, no extra modules), i2c-tools, gpiod.
D=/root/sit; mkdir -p $D; cd $D
res() { echo "CHECK $1 $2 ${3:-}"; }
info() { echo "INFO $*"; }
# sunxi pio: bank letter -> offset on the pinctrl gpiochip
off() { local b=$(( $(printf '%d' "'${1:1:1}") - 65 )); echo $(( b * 32 + ${1:2} )); }
# evidence <unit-addr> <dt-node>: why a controller is missing (dmesg, DT status, deferred probes, pinctrl)
evidence() { info "evidence $1: dmesg: $(dmesg | grep -E "$1|pinctrl.*(already requested|cannot claim)" | tail -6 | tr '\n' '|')"
  info "evidence $1: dt status: $(tr -d '\0' < /proc/device-tree/soc/$2/status 2>/dev/null || echo no-node) overlays-applied: $(ls /proc/device-tree/__symbols__ >/dev/null 2>&1 && echo symbols-present || echo no-symbols)"
  mount -t debugfs none /sys/kernel/debug 2>/dev/null
  info "evidence $1: devices_deferred: $(cat /sys/kernel/debug/devices_deferred 2>/dev/null | tr '\n' '|')"; }

if [ "$1" = wiring ]; then
  chip=$(gpiodetect 2>/dev/null | awk '/300b000.pinctrl/{print $1; exit}')
  [ -z "$chip" ] && { info "wiring: no pinctrl gpiochip from gpiodetect (gpiod missing?)"; echo WIRED_SPI=0; echo WIRED_I2C=0; echo ROUND-DONE; exit 0; }
  v2=0; gpioset --version 2>/dev/null | grep -qE '\) (2|[3-9])\.' && v2=1
  info "wiring: $chip, libgpiod v$([ $v2 = 1 ] && echo 2 || echo 1)"
  # follow A B: drive A, read B with the opposite pull bias; 1 if B follows A high and low
  follow() { local a=$(off $1) b=$(off $2) ok=1 v r
    for v in 1 0; do
      if [ $v2 = 1 ]; then bias=$([ $v = 1 ] && echo pull-down || echo pull-up)
        gpioset -c $chip $a=$v >/dev/null 2>&1 & p=$!; sleep 0.2
        r=$(gpioget -c $chip --bias=$bias $b 2>/dev/null); case "$r" in *inactive) r=0;; *active) r=1;; *) r=x;; esac
      else bias=$([ $v = 1 ] && echo pull-down || echo pull-up)
        gpioset -m signal $chip $a=$v >/dev/null 2>&1 & p=$!; sleep 0.2
        r=$(gpioget -B $bias $chip $b 2>/dev/null); [ "$r" != 0 ] && [ "$r" != 1 ] && r=x
      fi
      kill $p 2>/dev/null; wait $p 2>/dev/null
      [ "$r" = "$v" ] || ok=0
    done; echo $ok; }
  ws=1; for pr in PC5:PH6 PC6:PH7 PC7:PH8 PC8:PH5; do f=$(follow ${pr%:*} ${pr#*:}); info "wiring SPI $pr follows=$f"; [ $f = 1 ] || ws=0; done
  wi=1; for pr in PH2:PH4 PH3:PH5; do f=$(follow ${pr%:*} ${pr#*:}); info "wiring I2C $pr follows=$f"; [ $f = 1 ] || wi=0; done
  echo WIRED_SPI=$ws; echo WIRED_I2C=$wi; echo ROUND-DONE; exit 0
fi

MODE=$1; W=${2:-0}
echo "set: $MODE"; echo "kernel: $(uname -rv)"; echo "Image: $(readlink /boot/Image) dtb: $(readlink /boot/dtb/allwinner/sun50i-h616-orangepi-zero2.dtb 2>/dev/null || echo file)"
echo "overlays: $(grep -E '^(user_)?overlays=' /boot/armbianEnv.txt | tr '\n' ' ')"

if [ "$MODE" = checks-i2c ]; then
  WI=$W; info "wired: I2C=$WI"
  # ---- I2C target (TWI3 5002c00 with slave-24c02 at 0x64; TWI2 5002800 as the loopback host) ----
  # Job 31: TWI3 probed but was not /dev/i2c-3 (no i2cN aliases in the Zero2 DT -> dynamic bus numbers). The bus
  # numbers are now read from sysfs (adapter under the controller's platform device); the aliases (armbian-build
  # c6ce58c59) must make them 3 and 2, checked as W33-i2c-bus-number.
  busof() { local a; a=$(ls -d /sys/bus/platform/devices/$1/i2c-* 2>/dev/null | head -1); [ -n "$a" ] && echo ${a##*/i2c-}; }
  B3=$(busof 5002c00.i2c); B2=$(busof 5002800.i2c)
  info "adapters: $(for a in /sys/bus/i2c/devices/i2c-*; do [ -e $a/name ] && echo -n "${a##*/}=$(cat $a/name) "; done)"
  info "5002c00.i2c driver: $(basename "$(readlink /sys/bus/platform/devices/5002c00.i2c/driver 2>/dev/null)" 2>/dev/null) bus: ${B3:-none}; 5002800.i2c bus: ${B2:-none}"
  if [ "$B3" = 3 ] && [ "$B2" = 2 ]; then res W33-i2c-bus-number PASS "TWI3 5002c00 = i2c-3, TWI2 5002800 = i2c-2 (i2c aliases)"
  else res W33-i2c-bus-number FAIL "TWI3 5002c00 = i2c-${B3:-none} (want 3), TWI2 5002800 = i2c-${B2:-none} (want 2)"; fi
  if [ -n "$B3" ] && [ -e /dev/i2c-$B3 ]; then f=$(python3 $D/i2c_funcs.py $B3 2>&1)
    if [ $(( f & 0x20 )) -ne 0 ] 2>/dev/null; then res W33-i2c-target-func PASS "i2c-$B3 funcs $f has I2C_FUNC_SLAVE"; else res W33-i2c-target-func FAIL "i2c-$B3 funcs '$f' lacks I2C_FUNC_SLAVE (0x20)"; fi
  else res W33-i2c-target-func FAIL "no adapter under 5002c00.i2c (i2c3 did not probe with the sit-i2c3-slave overlay)"; evidence 5002c00 i2c@5002c00; B3=none; fi
  dev=/sys/bus/i2c/devices/$B3-1064
  if [ -d $dev ]; then drv=$(basename "$(readlink $dev/driver 2>/dev/null)"); sz=$(stat -c %s $dev/slave-eeprom 2>/dev/null)
    if [ "$drv" = i2c-slave-eeprom ] && [ "$sz" = 256 ]; then res W33-i2c-slave-eeprom-bind PASS "$B3-1064 driver $drv, slave-eeprom $sz bytes"
    else res W33-i2c-slave-eeprom-bind FAIL "$B3-1064 driver='$drv' slave-eeprom size='$sz' (reg_target failed?)"; fi
  else res W33-i2c-slave-eeprom-bind FAIL "no $dev"; fi
  # the same controller still works as a host with the target registered (scan of an otherwise empty bus returns)
  t0=$(date +%s); out=$(timeout 60 i2cdetect -y -r $B3 2>&1); rc=$?; dt=$(( $(date +%s) - t0 ))
  echo "$out" > i2cdetect-3.txt
  if [ $rc = 0 ]; then res W33-i2c-host-with-target PASS "i2cdetect -y -r $B3 rc 0 in ${dt}s"; else res W33-i2c-host-with-target FAIL "i2cdetect -y -r $B3 rc $rc in ${dt}s: $(echo "$out" | tail -1)"; fi
  info "i2cdetect $B3 found: $(echo "$out" | tail -n +2 | tr -s ' ' '\n' | grep -E '^[0-9a-f]{2}$' | tr '\n' ' ')"
  if [ "$WI" = 1 ]; then
    if [ -n "$B2" ] && [ -e /dev/i2c-$B2 ]; then
      o=$(timeout 30 python3 $D/i2c_loop.py $B2 0x64 16 2>&1); rc=$?
      [ $rc = 0 ] && res W33-i2c-loopback-16 PASS "i2c-$B2 -> 0x64: $o" || res W33-i2c-loopback-16 FAIL "rc $rc: $o"
      o=$(timeout 30 python3 $D/i2c_loop.py $B2 0x64 200 2>&1); rc=$?
      [ $rc = 0 ] && res W33-i2c-loopback-200 PASS "200 bytes round trip" || res W33-i2c-loopback-200 FAIL "rc $rc: ${o:0:120}"
      # the backend saw the bytes: slave-eeprom holds the 16-byte pattern at 0 after the 200-byte run (same prefix)
      want=$(python3 -c "print(bytes((0xa5+7*i)&0xff for i in range(16)).hex())"); got=$(dd if=$dev/slave-eeprom bs=1 count=16 2>/dev/null | xxd -p | tr -d '\n')
      [ "$got" = "$want" ] && res W33-i2c-slave-eeprom-content PASS "$got" || res W33-i2c-slave-eeprom-content FAIL "sysfs $got want $want"
      o=$(timeout 10 i2cset -y $B2 0x64 0xf0 0x5a 2>&1; timeout 10 i2cget -y $B2 0x64 0xf0 2>&1 | tail -1)
      case "$o" in *0x5a) res W33-i2c-loopback-i2cset PASS "i2cset/i2cget 0xf0 -> $o";; *) res W33-i2c-loopback-i2cset FAIL "$o";; esac
    else res W33-i2c-loopback-16 FAIL "no adapter under 5002800.i2c (sit-i2c2-ph overlay missing)"; evidence 5002800 i2c@5002800; fi
  else
    res W33-i2c-loopback-16 SKIP "NOT TESTED: no jumpers pin 5 PH4<->pin 8 PH2, pin 3 PH5<->pin 10 PH3 detected"
  fi
  info "dmesg i2c: $(dmesg | grep -iE 'i2c|twi|5002[8c]00|pinctrl' | grep -viE 'hdmi|ddc' | tail -8 | tr '\n' '|')"

elif [ "$MODE" = checks-spi ]; then
  WS=$W; info "wired: SPI=$WS"
  # ---- SPI target (SPI1 = spi1 target controller with the spidev handler from the overlay's "slave" child;
  #      spi-gpio on PC5-PC8 = spi2 loopback host) ----
  tgt=/sys/class/spi_slave/spi1
  if [ -d $tgt ]; then s=$(cat $tgt/slave 2>&1); e=$(dmesg | grep -ciE 'sun6i-spi.*(fail|error|cannot|timeout)|5011000.spi.*(fail|error)')
    [ "$s" = "spi-dev" ] && [ "$e" = 0 ] && res W33-spi-target-probe PASS "spi1 registered as a target, slave='$s', 0 error lines" || res W33-spi-target-probe FAIL "slave='$s' (want spi-dev) error lines=$e"
  else res W33-spi-target-probe FAIL "no /sys/class/spi_slave/spi1 ($(ls /sys/class/spi_slave/ 2>&1 | tr '\n' ' '))"; evidence 5011000 spi@5011000; fi
  if [ -d $tgt ]; then
    # the overlay's slave child (compatible armbian,spi-dev) gives /dev/spidev1.0 at boot (job 20: "echo spidev" never binds)
    if [ -c /dev/spidev1.0 ]; then res W33-spi-target-spidev PASS "/dev/spidev1.0 at boot from the overlay slave child ($(readlink -f /sys/class/spidev/spidev1.0/device/driver | xargs basename))"
    else res W33-spi-target-spidev FAIL "no /dev/spidev1.0: spi1.0 driver='$(readlink /sys/bus/spi/devices/spi1.0/driver 2>&1 | xargs basename)' modalias='$(cat /sys/bus/spi/devices/spi1.0/modalias 2>&1)'"
      info "evidence spidev: $(ls /sys/bus/spi/devices/ | tr '\n' ' ') lsmod: $(lsmod | grep -c spidev)"; fi
    if [ -c /dev/spidev1.0 ]; then
      # a target transfer blocks until a host clocks it; a signal must end it cleanly (interruptible wait)
      t0=$(date +%s); timeout -s INT 3 python3 $D/spi_xfer.py /dev/spidev1.0 16 00 >abort.out 2>&1; rc=$?; dt=$(( $(date +%s) - t0 ))
      if [ $dt -le 8 ] && ! pgrep -f "spi_xfer.py /dev/spidev1.0" >/dev/null; then res W33-spi-target-abort PASS "blocked transfer ended on SIGINT in ${dt}s (rc $rc)"; else res W33-spi-target-abort FAIL "rc $rc after ${dt}s, process left: $(pgrep -fa spi_xfer | head -1)"; fi
      if [ "$WS" = 1 ]; then
        if [ -c /dev/spidev2.0 ]; then
          for n in 16 100; do
            tpat=$(python3 -c "print(bytes((0x10+i)&0xff for i in range($n)).hex())"); hpat=$(python3 -c "print(bytes((0xe0-i)&0xff for i in range($n)).hex())")
            timeout 20 python3 $D/spi_xfer.py /dev/spidev1.0 $n $tpat 500000 > tgt-$n.out 2>&1 & tp=$!; sleep 0.7
            hrx=$(timeout 15 python3 $D/spi_xfer.py /dev/spidev2.0 $n $hpat 500000 2>&1); wait $tp; trc=$?; trx=$(cat tgt-$n.out)
            if [ "$hrx" = "$tpat" ] && [ "$trx" = "$hpat" ]; then res W33-spi-loopback-$n PASS "host got the target's $n bytes and the target the host's (target rc $trc)"
            else res W33-spi-loopback-$n FAIL "target rc $trc; host rx ${hrx:0:40} want ${tpat:0:40}; target rx ${trx:0:40} want ${hpat:0:40}"; fi
          done
        else res W33-spi-loopback-16 FAIL "no /dev/spidev2.0 (sit-spi-gpio-pc overlay missing)"; fi
      else
        res W33-spi-loopback-16 SKIP "NOT TESTED: no jumpers pin 13 PC5->23 PH6, 11 PC6->19 PH7, 22 PC7<-21 PH8, 15 PC8->3 PH5 detected"
      fi
      # handler swap from user space: "(null)" removes it, "spi-dev" (the spidev id table name) brings it back
      echo "(null)" > $tgt/slave 2>spi-slave-null.err; sleep 1
      [ -c /dev/spidev1.0 ] && res W33-spi-target-unregister FAIL "/dev/spidev1.0 still there after '(null)': $(cat spi-slave-null.err)" || res W33-spi-target-unregister PASS "spidev1.0 removed"
      echo spi-dev > $tgt/slave 2>spi-slave-store.err; sleep 1
      [ -c /dev/spidev1.0 ] && res W33-spi-target-reregister PASS "/dev/spidev1.0 back after 'echo spi-dev > slave' (slave='$(cat $tgt/slave)')" || res W33-spi-target-reregister FAIL "no /dev/spidev1.0 after 'echo spi-dev': $(cat spi-slave-store.err) slave='$(cat $tgt/slave 2>&1)'"
    fi
  fi
  [ -c /dev/spidev2.0 ] && info "spi-gpio host: $(readlink -f /sys/class/spidev/spidev2.0/device/../ 2>/dev/null | xargs basename 2>/dev/null)" || { info "no /dev/spidev2.0"; evidence spi-gpio spi-gpio; }
  info "dmesg spi: $(dmesg | grep -iE 'spi|501[01]000|pinctrl' | grep -viE 'spi-nor|mtd|m25p|flash' | tail -8 | tr '\n' '|')"
else
  echo "usage: board-sit.sh wiring | checks-spi <0|1> | checks-i2c <0|1>"; echo ROUND-DONE; exit 1
fi
dmesg | grep -iE 'oops|bug:|warning|call trace' | tail -5 | sed 's/^/INFO dmesg-warn: /'
echo ROUND-DONE
