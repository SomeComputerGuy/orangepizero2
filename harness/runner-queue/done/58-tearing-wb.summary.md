# Job 58-tearing-wb summary
Kernel: c43 (test-cumulative c65ef3449, Image md5 1a65e6a622f769e4f2bd2aa35c3f822f, fix 8af646391), uname -v "#45 SMP PREEMPT Fri Nov  6 18:34:31 UTC 2026".
DTB: sun50i-h616-orangepi-zero2.dtb.vdec-c43 md5 aa4d5bbb33e171e32c349e413c68f12c. Start 2026-11-06 18:40:20, end 18:50:29, exit code 0, chunks done: base, load (2 of 2).
Restored stock: 7.3.1-edge-sunxi64 #17 SMP PREEMPT Fri Oct 30 12:09:52 UTC 2026. Lock released.
Abnormal: runner.log "18:49:33 STALL: chunk load no output for 150 s, killing ssh" (after all load runs had results; chunk then marked done). ve.err: ffmpeg "Read error at pos 21945391 ... Immediate exit requested" and "Error opening input file /dev/shm/in.mkv" (loop restart at kill). dmesg_bad 0 in both chunks.

## Checks
0 PASS (no mode_unavailable, no missing)
1 PASS (selftest result pass, rc 0)
2 PASS (mixed/bad/wrong/full_bad/anomaly_lines all 0 in every run)
3 PASS (B: rc 0, fence 0, ok==flips==frames_checked; L: ok==flips, fence 0)
4 PASS (late 0, forced 0 in all runs incl. kmsg-rand)
5 PASS (flip_rate 60.003-60.004 in t-d0/d4/d12/rand; seq_gaps 0 <= deferred 0)
6 FAIL: latch_events_delta 0 and latch_events_now_delta 0 in every B run (need >= flips); latch_flushes_delta == flips+3. commits_outside_blanking part holds: t-d4 599, t-d12 599 (>=590).
7 NOT TESTED for VE load: ve_irqs_delta 95 (ve-d4), 94 (ve-rand), 89 (vemem-rand), 94 (kmsg-rand) are not > 100; no ve_download_failed. Runs still judged by 2-4 as plain runs (PASS).
8 PASS (base and load dmesg_bad 0)
Overall: FAIL on check 6 (event counters stay 0; no tearing seen).

## Table (flips ok wrong mixed bad fence full_bad rate seq_gaps | late deferred forced events events_now stale_cleared wb_ovf wb_timeout | outside_blank ve_irqs line_max line_deadline)
t-d0 600 600 0 0 0 0 0 60.003 0 0 0 0 0 0 2 0 0 0 0 5 32
t-d4 600 600 0 0 0 0 0 60.003 0 0 0 0 0 0 2 0 0 599 0 6 32
t-d12 600 600 0 0 0 0 0 60.004 0 0 0 0 0 0 2 0 0 599 0 6 32
t-rand 1200 1200 0 0 0 0 0 60.004 0 0 0 0 0 0 2 0 0 1157 0 8 32
burst1 60 60 0 0 0 0 0 60.003 0 0 0 0 0 0 2 0 0 59 0 8 32
burst2 60 60 0 0 0 0 0 60.003 0 0 0 0 0 0 2 0 0 59 0 8 32
burst3 60 60 0 0 0 0 0 60.003 0 0 0 0 0 0 2 0 0 59 0 8 32
burst4 60 60 0 0 0 0 0 60.005 0 0 0 0 0 0 2 0 0 59 0 8 32
ve-d4 600 600 0 0 0 0 0 60.003 0 0 0 0 0 0 2 0 0 599 95 3 32
ve-rand 600 600 0 0 0 0 0 59.408 6 0 0 0 0 0 2 0 0 585 94 13 32
mem-d4 600 600 0 0 0 0 0 50.837 87 0 0 0 0 0 2 0 0 599 0 13 32
mem-rand 600 600 0 0 0 0 0 48.768 110 0 0 0 0 0 2 0 0 583 0 13 32
vemem-rand 600 600 0 0 0 0 0 48.702 105 0 0 0 0 0 2 0 0 587 89 25 32
kmsg-rand 600 600 0 0 0 0 0 56.424 38 0 0 0 0 0 2 0 0 584 94 25 32

memload_GBps: mem-d4 2.372, mem-rand 2.378, vemem-rand 2.069
printk.txt: '1 4 1 7' (x2, base and load)
No WRONG/MIXED/BAD lines.
Logs: harness/research/display-tearing/logs/runner-t58/
