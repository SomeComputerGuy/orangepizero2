#!/bin/bash
# board-dsw.sh: mechanical checks for the datasheet W-items (runner job 19). Runs on the Zero2 as root,
# on the newest cumulative kernel with the user overlays dsw-spdif-out, dsw-i2s3-ph, dsw-ahub-dam applied.
# Output: one "CHECK <item> PASS|FAIL|SKIP <value>" line per check, "INFO" lines, then ROUND-DONE.
# Needs /root/dsw/busybox-armhf (static armhf busybox) and /root/dsw/di300test (static aarch64).
# The half-duplex test (W31) bounces end0, so it runs detached at the end (hd.sh -> hd.txt); the host reads hd.txt.
D=/root/dsw; mkdir -p $D; cd $D
res() { echo "CHECK $1 $2 ${3:-}"; }
info() { echo "INFO $*"; }
echo "kernel: $(uname -rv)"; echo "Image: $(readlink /boot/Image)"
echo "overlays: $(grep -E '^(user_)?overlays=' /boot/armbianEnv.txt | tr '\n' ' ')"
mount | grep -q debugfs || mount -t debugfs none /sys/kernel/debug 2>/dev/null

# W3: high-speed timer registered as a clocksource
cs=$(cat /sys/devices/system/clocksource/clocksource0/available_clocksource 2>/dev/null)
case " $cs " in *" hstimer "*) res W3-hstimer PASS "$cs";; *) res W3-hstimer FAIL "available_clocksource='$cs'";; esac
info "current_clocksource $(cat /sys/devices/system/clocksource/clocksource0/current_clocksource)"

# W6: AArch32 execution state (CONFIG_COMPAT): a static armhf busybox (ELF32 ARM) runs at all, and `linux32 uname -m`
# from it says armv8l. uname -m of a compat task is the native "aarch64" unless the PER_LINUX32 personality is set, which
# arm64 does not do for compat tasks (job 19 expected armv8l without linux32: wrong expectation).
if [ -x $D/busybox-armhf ]; then ok=$($D/busybox-armhf echo compat-ok 2>&1 | head -1); m=$($D/busybox-armhf uname -m 2>&1 | head -1)
  if command -v linux32 > /dev/null; then L32="linux32"; elif command -v setarch > /dev/null; then L32="setarch linux32"; else L32="$D/busybox-armhf linux32"; fi
  m32=$($L32 $D/busybox-armhf uname -m 2>&1 | head -1)
  [ "$ok" = compat-ok ] && [ "$m32" = armv8l ] && res W6-compat PASS "armhf busybox runs; uname -m '$m' native, '$m32' under $L32" || res W6-compat FAIL "run='$ok' uname -m='$m' $L32 uname -m='$m32'"
  info "compat32 maps: $($D/busybox-armhf cat /proc/self/maps 2>/dev/null | grep -oE '\[(vectors|sigpage|vdso)\]' | sort -u | tr '\n' ' ')"
else res W6-compat SKIP "no $D/busybox-armhf"; fi

# W5: SPI NOR dual read (1S-1S-2S), data intact (eGON.BT0 magic, two identical reads)
p=/sys/kernel/debug/spi-nor/spi0.0/params
if [ -f $p ]; then proto=$(awk '/^protocols/{f=1} f && $1=="read"{print $2; exit}' $p); op=$(awk '/^opcodes/{f=1} f && $1=="read"{print $2; exit}' $p)
  [ "$proto" = 1S-1S-2S ] && res W5-spi-dual-proto PASS "read $proto opcode $op" || res W5-spi-dual-proto FAIL "read proto '$proto' opcode $op"
else res W5-spi-dual-proto FAIL "no $p"; fi
if [ -e /dev/mtd0ro ]; then t0=$(date +%s.%N); s1=$(sha256sum /dev/mtd0ro | cut -c1-64); t1=$(date +%s.%N); s2=$(sha256sum /dev/mtd0ro | cut -c1-64)
  magic=$(dd if=/dev/mtd0ro bs=1 skip=4 count=8 2>/dev/null); dt=$(awk -v a=$t0 -v b=$t1 'BEGIN{printf "%.2f", b-a}')
  if [ "$s1" = "$s2" ] && [ "$magic" = "eGON.BT0" ]; then res W5-spi-nor-read PASS "2 MiB in ${dt}s, eGON.BT0 at 4, sha256 ${s1:0:16}"; else res W5-spi-nor-read FAIL "s1=${s1:0:16} s2=${s2:0:16} magic='$magic' ${dt}s"; fi
  [ "$s1" = 711306f6434bee747ab96f911e5de251f87e5442e6ed33b2350cffa5522ee933 ] && info "mtd0 sha256 = 11-03 baseline" || info "mtd0 sha256 differs from the 11-03 baseline (U-Boot in SPI may have been reflashed since): $s1"
else res W5-spi-nor-read FAIL "no /dev/mtd0ro"; fi

# W10: SDIO UHS timing for the UWE5622 on mmc1, no mmc1 errors, WiFi scan works
ios=/sys/kernel/debug/mmc1/ios
if [ -f $ios ]; then tim=$(grep -i '^timing spec' $ios | sed 's/.*(//; s/)//'); clk=$(grep -i '^clock:' $ios | awk '{print $2}')
  case "$tim" in *uhs*|*UHS*|*SDR104*|*DDR50*|*SDR50*) res W10-sdio-uhs PASS "$tim, clock $clk Hz";; *) res W10-sdio-uhs FAIL "timing '$tim', clock $clk Hz";; esac
else res W10-sdio-uhs FAIL "no $ios"; fi
e=$(dmesg | grep -ciE 'mmc1: .*(error|timeout|fail)'); [ "$e" = 0 ] && res W10-mmc1-dmesg PASS "0 error lines" || res W10-mmc1-dmesg FAIL "$e error lines: $(dmesg | grep -iE 'mmc1: .*(error|timeout|fail)' | tail -2 | tr '\n' '|')"
ip link set wlan0 up 2>/dev/null; n=$(timeout 30 iw dev wlan0 scan 2>/dev/null | grep -c 'SSID:'); [ "${n:-0}" -ge 1 ] && res W10-wifi-scan PASS "$n SSIDs" || res W10-wifi-scan FAIL "$n SSIDs"

# WiFi 32 kHz LPO clock (impl-small-gaps 8a): osc32k-fanout enabled
en=$(awk '$1=="osc32k-fanout"{print $2; exit}' /sys/kernel/debug/clk/clk_summary); [ "${en:-0}" -ge 1 ] && res SG8a-osc32k-fanout PASS "enable_cnt $en" || res SG8a-osc32k-fanout FAIL "enable_cnt '$en'"

# Sound cards present (informative: the index order decides what ALSA "default" is)
info "asound cards: $(sed -n 's/^ *\([0-9]\) \[\([^]]*\)\].*/\1=\2/p' /proc/asound/cards | tr -s ' ' | tr '\n' ' ')"
cardno() { awk -v n="$1" '$0 ~ n {print $1; exit}' /proc/asound/cards; }

# W17: codec DRC controls
c=$(cardno 'H616 Audio Codec')
if [ -n "$c" ]; then n=$(amixer -c "$c" controls | grep -c 'DRC'); [ "$n" -ge 7 ] && res W17-codec-drc PASS "$n DRC controls" || res W17-codec-drc FAIL "$n DRC controls"
  info "codec DRC: $(amixer -c "$c" controls | grep -E 'DRC|HPF' | sed 's/.*name=//' | tr '\n' ';')"
else res W17-codec-drc FAIL "no 'H616 Audio Codec' card"; fi

# W19: S/PDIF card from the spdif-out overlay; the module clock follows the sample rate (fix/sunxi-h616-spdif-clk-rate)
c=$(cardno '[[]SPDIF')
if [ -n "$c" ]; then res W19-spdif-card PASS "card $c"
  for r in 48000 44100; do exp=24576000; [ $r = 44100 ] && exp=22579200
    timeout 10 aplay -q -D hw:$c,0 -r $r -f S16_LE -c 2 -t raw /dev/zero > aplay-spdif-$r.txt 2>&1 & pid=$!; sleep 3
    rate=$(cat /sys/kernel/debug/clk/spdif/clk_rate 2>/dev/null); kill $pid 2>/dev/null; wait $pid 2>/dev/null; rc=$?
    d=$(( rate > exp ? rate - exp : exp - rate ))
    if [ -n "$rate" ] && [ $d -le $((exp / 1000)) ]; then res W19-spdif-clk-$r PASS "spdif clk $rate Hz (expected $exp)"; else res W19-spdif-clk-$r FAIL "spdif clk '$rate' Hz, expected $exp; aplay: $(head -c 120 aplay-spdif-$r.txt | tr '\n' ' ')"; fi
  done
  info "spdif pins: $(grep -E 'PH4' /sys/kernel/debug/pinctrl/*pio*/pinmux-pins 2>/dev/null | head -1)"
else res W19-spdif-card FAIL "no SPDIF card: $(cat /proc/asound/cards | tr '\n' ' ')"; fi

# W18: I2S3 card from the i2s3-ph overlay streams both ways (no wiring: data is not checked); DAM card controls
c=$(cardno 'ahubi2s3')
if [ -n "$c" ]; then res W18-i2s3-card PASS "card $c"
  timeout 15 aplay -q -D hw:$c,0 -r 48000 -f S32_LE -c 2 -t raw -d 2 /dev/zero > aplay-i2s3.txt 2>&1; rc=$?
  [ $rc = 0 ] && res W18-i2s3-play PASS "aplay 2 s rc 0" || res W18-i2s3-play FAIL "rc $rc: $(head -c 120 aplay-i2s3.txt | tr '\n' ' ')"
  timeout 15 arecord -q -D hw:$c,0 -r 48000 -f S32_LE -c 2 -t raw -d 2 i2s3-rec.raw > arecord-i2s3.txt 2>&1; rc=$?
  [ $rc = 0 ] && [ "$(stat -c %s i2s3-rec.raw)" -gt 0 ] && res W18-i2s3-capture PASS "arecord 2 s rc 0, $(stat -c %s i2s3-rec.raw) bytes" || res W18-i2s3-capture FAIL "rc $rc: $(head -c 120 arecord-i2s3.txt | tr '\n' ' ')"
  info "i2s3 pins: $(grep -cE 'PH[5-9] ' /sys/kernel/debug/pinctrl/*pio*/pinmux-pins 2>/dev/null) PH5-PH9 lines in pinmux-pins"
else res W18-i2s3-card FAIL "no ahubi2s3 card"; res W18-i2s3-play SKIP; res W18-i2s3-capture SKIP; fi
c=$(cardno 'ahubdam')
if [ -n "$c" ]; then n=$(amixer -c "$c" controls | grep -c 'Src Select'); [ "$n" = 13 ] && res W18-dam-controls PASS "card $c, $n Src Select controls" || res W18-dam-controls FAIL "card $c, $n Src Select controls (expected 13)"
  info "dam I2S3 Src: $(amixer -c "$c" cget name='I2S3 Src Select' 2>/dev/null | tail -1)"
else res W18-dam-controls FAIL "no ahubdam card"; fi
# ALSA "default" with the extra cards present (informative; a PCM-less card at index 0 would break it)
timeout 10 aplay -q -D default -r 48000 -f S16_LE -c 2 -t raw -d 1 /dev/zero > aplay-default.txt 2>&1; info "aplay -D default rc $? ($(head -c 100 aplay-default.txt | tr '\n' ' '))"

# W11: DE33 planes and the pixel blend mode property (no display needed; modetest lists planes without a connector)
if command -v modetest > /dev/null; then modetest -M sun4i-drm -p > modetest.txt 2>&1
  np=$(awk '/^Planes:/{p=1; next} /^Frame buffers:/{p=0} p && /^[0-9]+\t/{n++} END{print n+0}' modetest.txt); nb=$(grep -c 'pixel blend mode' modetest.txt); na=$(grep -c '^[[:space:]]*[0-9]* alpha:' modetest.txt)
  [ "$np" -ge 4 ] && [ "$nb" -ge 1 ] && res W11-de33-planes PASS "$np planes, $nb with pixel blend mode, $na with alpha" || res W11-de33-planes FAIL "$np planes, $nb with pixel blend mode"
  info "plane formats: $(awk '/^Planes:/{p=1} /^Frame buffers:/{p=0} p && /formats:/{print NF-1" fmts"}' modetest.txt | tr '\n' ' ')"
else res W11-de33-planes SKIP "no modetest"; fi

# W13: DI300 deinterlacer: device, IOMMU master, v4l2-compliance, weave round trip
dev=; for v in /sys/class/video4linux/video*; do case "$(cat $v/name 2>/dev/null)" in *di300*|*deinterlace*) dev=/dev/$(basename $v);; esac; done
if [ -n "$dev" ]; then res W13-di300-dev PASS "$dev ($(cat /sys/class/video4linux/$(basename $dev)/name))"
  g=$(ls -d /sys/kernel/iommu_groups/*/devices/1420000.deinterlace 2>/dev/null | wc -l); [ "$g" = 1 ] && res W13-di300-iommu PASS "1420000.deinterlace in an iommu group" || res W13-di300-iommu FAIL "iommu group entries: $g"
  v4l2-compliance -d $dev > compliance-di.txt 2>&1; tot=$(grep -E '^Total for' compliance-di.txt | tail -1); f=$(echo "$tot" | sed -n 's/.*Failed: \([0-9]*\).*/\1/p')
  [ "$f" = 0 ] && res W13-di300-compliance PASS "$tot" || res W13-di300-compliance FAIL "$tot"
  if [ -x $D/di300test ]; then head -c $((32*32*3/2*8)) /dev/urandom > in32.nv12
    timeout 60 $D/di300test -W 32 -H 32 -f nv12 -m weave -c weave -d $dev -i in32.nv12 -o out32.nv12 > di-weave32.txt 2>&1; rc=$?
    [ $rc = 0 ] && res W13-di300-weave PASS "32x32 NV12 x8 weave rc 0, $(tail -1 di-weave32.txt | head -c 80)" || res W13-di300-weave FAIL "rc $rc: $(tail -2 di-weave32.txt | tr '\n' ' ' | head -c 160)"
    head -c $((720*576*3/2*6)) /dev/urandom > in720.nv12
    timeout 60 $D/di300test -W 720 -H 576 -f nv12 -m weave -c weave -d $dev -i in720.nv12 -o out720.nv12 > di-weave720.txt 2>&1; rc=$?
    [ $rc = 0 ] && res W13-di300-weave720 PASS "720x576 NV12 x6 weave rc 0" || res W13-di300-weave720 FAIL "rc $rc: $(tail -2 di-weave720.txt | tr '\n' ' ' | head -c 160)"
  else res W13-di300-weave SKIP "no $D/di300test"; fi
else res W13-di300-dev FAIL "no di300 video device: $(for v in /sys/class/video4linux/video*; do echo -n "$(basename $v)=$(cat $v/name) "; done)"; fi

# W15: TVE connector status is reported (expansion overlay not applied here: the TVE is then absent, informative only)
info "drm connectors: $(for c in /sys/class/drm/card0-*; do echo -n "$(basename $c)=$(cat $c/status) "; done)"

# W4/TRNG: hwrng present (PRNG is N/A upstream)
info "hwrng current: $(cat /sys/class/misc/hw_random/rng_current 2>/dev/null)"

# W31: half duplex, detached (bounces end0); the host reads $D/hd.txt about 60 s later
cat > $D/hd.sh <<'HD'
#!/bin/bash
D=/root/dsw; : > $D/hd.txt; restore() { ethtool -s end0 autoneg on 2>/dev/null; }; trap restore EXIT
if ! command -v ethtool > /dev/null; then echo "SKIP no ethtool" > $D/hd.txt; exit 0; fi
for s in 100 10; do
  ethtool -s end0 speed $s duplex half autoneg off 2>> $D/hd.err; sleep 8
  sp=$(ethtool end0 | awk '/Speed:/{print $2}'); du=$(ethtool end0 | awk '/Duplex:/{print $2}'); li=$(ethtool end0 | awk '/Link detected:/{print $3}')
  rx=$(ping -c 5 -W 2 -i 0.3 10.56.0.1 2>/dev/null | awk -F'[ ,]+' '/received/{for(i=1;i<=NF;i++) if($i=="received") print $(i-1)}')
  echo "forced $s half: speed $sp duplex $du link $li ping-received ${rx:-0}/5" >> $D/hd.txt
done
# autoneg restored: wait for the link to come back up (up to 40 s; it took > 10 s in job 19), then print the whole
# Speed/Duplex/Auto-negotiation/Link lines (job 19 printed only two awk fields, so "Link detected: yes" lost its value)
restore; for i in $(seq 1 20); do sleep 2; ethtool end0 2>/dev/null | grep -q 'Link detected: yes' && break; done
echo "autoneg on: $(ethtool end0 | awk '/Speed:|Duplex:|Auto-negotiation:|Link detected:/{sub(/^[ \t]+/, ""); printf "%s ", $0}')after $((i * 2))s" >> $D/hd.txt; echo HD-DONE >> $D/hd.txt
HD
chmod +x $D/hd.sh; setsid nohup bash $D/hd.sh > $D/hd.log 2>&1 < /dev/null &
echo "INFO half-duplex test started detached (hd.sh), results in $D/hd.txt"
echo ROUND-DONE
