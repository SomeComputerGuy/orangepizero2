# Job 68-vk11-main chunk 1 summary (2026-11-07)
Result: BLOCKED at setup, 0 parts run this chunk (script exit 2). Job stays in the queue. Parts done: 1 of 64 (stale from earlier; part-00 only), remaining 63.
BLOCKED reason (harness/research/vk11/logs/runner/BLOCKED): rsync of the frozen vk3 failed
Exact lines (runner output):
  kernel: #51 SMP PREEMPT Fri Nov  6 20:28:54 UTC 2026   (c48 trial kernel, fix present)
  rsync: [Receiver] mkdir "/root/opiz2-mesa/vk3" failed: No such file or directory (2)
  rsync error: error in file IO (code 11) at main.c(808) [Receiver=3.5.0]
  2026-11-07 05:29:21 BLOCKED: rsync of the frozen vk3 failed
Likely cause: the reflash (job 69) removed /root/opiz2-mesa on the board; the parent dir does not exist so rsync cannot mkdir vk3 (script needs mkdir -p /root/opiz2-mesa first, or stage the dir). Not fixed by the runner (no edits allowed).
Restored: 7.3.3-edge-sunxi64 #21 SMP PREEMPT Fri Nov 6 18:18:30 UTC 2026; lock released (runner-vk11-1794029248).
--check output was run, but its lines are STALE (from the earlier chunk-1 data, 1 part): checks 1,2,3b,4,6,7,8,9 PASS; 3 FAIL (d9); 5 FAIL (1 of 64); INFO BLOCKED: rsync of the frozen vk3 failed. Pass=16333 NotSupported=34410, Hang 0, Soft-stop 0.
