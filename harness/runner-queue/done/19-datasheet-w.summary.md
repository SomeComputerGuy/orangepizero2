# 19-datasheet-w: FAIL (3 CHECK FAIL lines: W6-compat, W18-dam-controls, W31-autoneg-restored)
Start 2026-11-05 23:33:22 UTC, end 23:37:35 UTC. ROUND-DONE=1 PASS. Overall: 3 FAIL. dmesg.txt: no Page fault/timed out/Oops/BUG:/WARNING lines. restored line ok (vmlinuz-7.3.1-edge-sunxi64, 0 overlays left).
```
kernel: 7.3.1 #19 SMP PREEMPT Thu Nov  5 23:14:46 UTC 2026
overlays: user_overlays=dsw-spdif-out dsw-i2s3-ph dsw-ahub-dam 
CHECK W3-hstimer PASS arch_sys_counter timer hstimer 
CHECK W6-compat FAIL uname -m='aarch64'
CHECK W5-spi-dual-proto PASS read 1S-1S-2S opcode 0x3b
CHECK W5-spi-nor-read PASS 2 MiB in 0.30s, eGON.BT0 at 4, sha256 557e5f3da8522563
CHECK W10-sdio-uhs PASS sd uhs SDR104, clock 150000000 Hz
CHECK W10-mmc1-dmesg PASS 0 error lines
CHECK W10-wifi-scan PASS 10 SSIDs
CHECK SG8a-osc32k-fanout PASS enable_cnt 1
INFO asound cards: 0=Codec  1=SPDIF  2=ahubi2s3  3=HDMI  
CHECK W17-codec-drc PASS 7 DRC controls
CHECK W19-spdif-card PASS card 1
CHECK W19-spdif-clk-48000 PASS spdif clk 24576000 Hz (expected 24576000)
CHECK W19-spdif-clk-44100 PASS spdif clk 22579200 Hz (expected 22579200)
CHECK W18-i2s3-card PASS card 2
CHECK W18-i2s3-play PASS aplay 2 s rc 0
CHECK W18-i2s3-capture PASS arecord 2 s rc 0, 768000 bytes
CHECK W18-dam-controls FAIL no ahubdam card
INFO aplay -D default rc 0 ()
CHECK W11-de33-planes PASS 6 planes, 6 with pixel blend mode, 6 with alpha
CHECK W13-di300-dev PASS /dev/video1 (sun50i-di300)
CHECK W13-di300-iommu PASS 1420000.deinterlace in an iommu group
CHECK W13-di300-compliance PASS Total for sun50i-di300 device /dev/video1: 49, Succeeded: 49, Failed: 0, Warnings: 0
CHECK W13-di300-weave PASS 32x32 NV12 x8 weave rc 0, weave check: PASS (0 mismatching frames)
CHECK W13-di300-weave720 PASS 720x576 NV12 x6 weave rc 0
CHECK W31-half-100 PASS forced 100 half: speed 100Mb/s duplex Half link yes ping-received 5/5
CHECK W31-half-10 PASS forced 10 half: speed 10Mb/s duplex Half link yes ping-received 5/5
CHECK W31-autoneg-restored FAIL autoneg on: Speed: 1000Mb/s Duplex: Full Link detected: 
--- hd.txt
forced 100 half: speed 100Mb/s duplex Half link yes ping-received 5/5
forced 10 half: speed 10Mb/s duplex Half link yes ping-received 5/5
autoneg on: Speed: 1000Mb/s Duplex: Full Link detected: 
HD-DONE
--- runner.log
2026-11-05 23:37:35 restored: #17 SMP PREEMPT Fri Oct 30 12:09:52 UTC 2026 vmlinuz-7.3.1-edge-sunxi64 0 
```
Results: harness/research/datasheet-w/logs/runner/
