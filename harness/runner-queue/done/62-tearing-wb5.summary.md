# Job 62-tearing-wb5 summary
Kernel c47 (Image md5 b3938b2633e1bcc7cf9d5262fa66b5d1, fix 825596b48); trial uname/DTB: dtb sun50i-h616-orangepi-zero2.dtb.vdec-c47 md5 aa4d5bbb33e171e32c349e413c68f12c
Start 2026-11-06 20:10:45, end 20:20:08, exit 0, chunks base+load done. Restored uname -v: #17 SMP PREEMPT Fri Oct 30 12:09:52 UTC 2026 (stock). Lock released.
## Check verdicts: 0-9 all PASS (no mode_unavailable, no missing, selftest pass rc 0, no STALL, 2 chunks done, dmesg_bad 0 both, ve_leftover 0, no 'Error opening input file').
Check 5 kmsg-rand: report only (acct_unexplained 0 anyway). Results: harness/research/display-tearing/logs/runner-t62/results.txt
## VE load
VE load started pid 6341 (-hwaccel_output_format drm_prime), 69 VE IRQs in 2 s
VE load started pid 7850 (-hwaccel_output_format drm_prime), 69 VE IRQs in 2 s
## memload_GBps
load mem-d4 memload_GBps 2.371
load mem-rand memload_GBps 2.365
load vemem-rand memload_GBps 0.745
load vemem-rand2 memload_GBps 0.997
load vemem-rand3 memload_GBps 0.963
## Per run (all keys of interest from results.txt)
### flips
base/t-d0=600  base/t-d4=600  base/t-d12=600  base/t-rand=1200  base/burst1=60  base/burst2=60  base/burst3=60  base/burst4=60  load/ve-d4=600  load/ve-rand=600  load/mem-d4=600  load/mem-rand=600  load/vemem-rand=600  load/vemem-rand2=600  load/vemem-rand3=600  load/kmsg-rand=600  
### ok
base/t-d0=600  base/t-d4=600  base/t-d12=600  base/t-rand=1200  base/burst1=60  base/burst2=60  base/burst3=60  base/burst4=60  load/ve-d4=599  load/ve-rand=600  load/mem-d4=600  load/mem-rand=600  load/vemem-rand=599  load/vemem-rand2=598  load/vemem-rand3=596  load/kmsg-rand=600  
### wrong
base/t-d0=0  base/t-d4=0  base/t-d12=0  base/t-rand=0  base/burst1=0  base/burst2=0  base/burst3=0  base/burst4=0  load/ve-d4=0  load/ve-rand=0  load/mem-d4=0  load/mem-rand=0  load/vemem-rand=0  load/vemem-rand2=0  load/vemem-rand3=0  load/kmsg-rand=0  
### mixed
base/t-d0=0  base/t-d4=0  base/t-d12=0  base/t-rand=0  base/burst1=0  base/burst2=0  base/burst3=0  base/burst4=0  load/ve-d4=0  load/ve-rand=0  load/mem-d4=0  load/mem-rand=0  load/vemem-rand=0  load/vemem-rand2=0  load/vemem-rand3=0  load/kmsg-rand=0  
### bad
base/t-d0=0  base/t-d4=0  base/t-d12=0  base/t-rand=0  base/burst1=0  base/burst2=0  base/burst3=0  base/burst4=0  load/ve-d4=0  load/ve-rand=0  load/mem-d4=0  load/mem-rand=0  load/vemem-rand=0  load/vemem-rand2=0  load/vemem-rand3=0  load/kmsg-rand=0  
### fence_errors
base/t-d0=0  base/t-d4=0  base/t-d12=0  base/t-rand=0  base/burst1=0  base/burst2=0  base/burst3=0  base/burst4=0  load/ve-d4=1  load/ve-rand=0  load/mem-d4=0  load/mem-rand=0  load/vemem-rand=1  load/vemem-rand2=2  load/vemem-rand3=4  load/kmsg-rand=0  
### full_bad
base/t-d0=0  base/t-d4=0  base/t-d12=0  base/t-rand=0  base/burst1=0  base/burst2=0  base/burst3=0  base/burst4=0  load/ve-d4=0  load/ve-rand=0  load/mem-d4=0  load/mem-rand=0  load/vemem-rand=0  load/vemem-rand2=0  load/vemem-rand3=0  load/kmsg-rand=0  
### flip_rate
base/t-d0=60.003  base/t-d4=60.004  base/t-d12=60.004  base/t-rand=60.004  base/burst1=60.004  base/burst2=60.003  base/burst3=60.004  base/burst4=60.006  load/ve-d4=53.169  load/ve-rand=47.859  load/mem-d4=54.458  load/mem-rand=53.886  load/vemem-rand=47.988  load/vemem-rand2=48.505  load/vemem-rand3=48.901  load/kmsg-rand=60.004  
### seq_gaps
base/t-d0=0  base/t-d4=0  base/t-d12=0  base/t-rand=0  base/burst1=0  base/burst2=0  base/burst3=0  base/burst4=0  load/ve-d4=77  load/ve-rand=152  load/mem-d4=48  load/mem-rand=50  load/vemem-rand=150  load/vemem-rand2=140  load/vemem-rand3=135  load/kmsg-rand=0  
### latch_flushes_late_delta
base/probe=0  base/t-d0=0  base/t-d4=0  base/t-d12=0  base/t-rand=0  base/burst1=0  base/burst2=0  base/burst3=0  base/burst4=0  load/ve-d4=0  load/ve-rand=0  load/mem-d4=0  load/mem-rand=0  load/vemem-rand=0  load/vemem-rand2=0  load/vemem-rand3=0  load/kmsg-rand=0  
### latch_deferred_delta
base/probe=0  base/t-d0=0  base/t-d4=0  base/t-d12=0  base/t-rand=0  base/burst1=0  base/burst2=0  base/burst3=0  base/burst4=0  load/ve-d4=0  load/ve-rand=0  load/mem-d4=0  load/mem-rand=0  load/vemem-rand=0  load/vemem-rand2=2  load/vemem-rand3=1  load/kmsg-rand=0  
### latch_forced_delta
base/probe=0  base/t-d0=0  base/t-d4=0  base/t-d12=0  base/t-rand=0  base/burst1=0  base/burst2=0  base/burst3=0  base/burst4=0  load/ve-d4=0  load/ve-rand=0  load/mem-d4=0  load/mem-rand=0  load/vemem-rand=0  load/vemem-rand2=0  load/vemem-rand3=0  load/kmsg-rand=0  
### latch_events_delta
base/probe=4  base/t-d0=603  base/t-d4=603  base/t-d12=603  base/t-rand=1203  base/burst1=63  base/burst2=63  base/burst3=63  base/burst4=63  load/ve-d4=603  load/ve-rand=602  load/mem-d4=603  load/mem-rand=603  load/vemem-rand=601  load/vemem-rand2=600  load/vemem-rand3=603  load/kmsg-rand=603  
### latch_events_now_delta
base/probe=0  base/t-d0=0  base/t-d4=0  base/t-d12=0  base/t-rand=0  base/burst1=0  base/burst2=0  base/burst3=0  base/burst4=0  load/ve-d4=1  load/ve-rand=1  load/mem-d4=0  load/mem-rand=0  load/vemem-rand=2  load/vemem-rand2=3  load/vemem-rand3=0  load/kmsg-rand=0  
### latch_coalesced_delta
base/probe=0  base/t-d0=0  base/t-d4=0  base/t-d12=0  base/t-rand=0  base/burst1=0  base/burst2=0  base/burst3=0  base/burst4=0  load/ve-d4=0  load/ve-rand=0  load/mem-d4=0  load/mem-rand=0  load/vemem-rand=0  load/vemem-rand2=0  load/vemem-rand3=0  load/kmsg-rand=0  
### events_got
base/t-d0=600  base/t-d4=600  base/t-d12=600  base/t-rand=1200  base/burst1=60  base/burst2=60  base/burst3=60  base/burst4=60  load/ve-d4=600  load/ve-rand=600  load/mem-d4=600  load/mem-rand=600  load/vemem-rand=600  load/vemem-rand2=600  load/vemem-rand3=600  load/kmsg-rand=600  
### events_unheld
base/t-d0=0  base/t-d4=0  base/t-d12=0  base/t-rand=0  base/burst1=0  base/burst2=0  base/burst3=0  base/burst4=0  load/ve-d4=0  load/ve-rand=0  load/mem-d4=0  load/mem-rand=0  load/vemem-rand=0  load/vemem-rand2=0  load/vemem-rand3=0  load/kmsg-rand=0  
### events_unflushed
base/t-d0=0  base/t-d4=0  base/t-d12=0  base/t-rand=0  base/burst1=0  base/burst2=0  base/burst3=0  base/burst4=0  load/ve-d4=0  load/ve-rand=0  load/mem-d4=0  load/mem-rand=0  load/vemem-rand=0  load/vemem-rand2=0  load/vemem-rand3=0  load/kmsg-rand=0  
### wb_failed_delta
base/probe=0  base/t-d0=0  base/t-d4=0  base/t-d12=0  base/t-rand=0  base/burst1=0  base/burst2=0  base/burst3=0  base/burst4=0  load/ve-d4=1  load/ve-rand=0  load/mem-d4=0  load/mem-rand=0  load/vemem-rand=1  load/vemem-rand2=2  load/vemem-rand3=4  load/kmsg-rand=0  
### wb_overflow_delta
base/probe=0  base/t-d0=0  base/t-d4=0  base/t-d12=0  base/t-rand=0  base/burst1=0  base/burst2=0  base/burst3=0  base/burst4=0  load/ve-d4=1  load/ve-rand=0  load/mem-d4=0  load/mem-rand=0  load/vemem-rand=0  load/vemem-rand2=0  load/vemem-rand3=0  load/kmsg-rand=0  
### wb_timeout_delta
base/probe=0  base/t-d0=0  base/t-d4=0  base/t-d12=0  base/t-rand=0  base/burst1=0  base/burst2=0  base/burst3=0  base/burst4=0  load/ve-d4=0  load/ve-rand=0  load/mem-d4=0  load/mem-rand=0  load/vemem-rand=0  load/vemem-rand2=0  load/vemem-rand3=0  load/kmsg-rand=0  
### wb_busy_frames_delta
base/probe=0  base/t-d0=0  base/t-d4=0  base/t-d12=0  base/t-rand=0  base/burst1=0  base/burst2=0  base/burst3=0  base/burst4=0  load/ve-d4=0  load/ve-rand=0  load/mem-d4=0  load/mem-rand=0  load/vemem-rand=1  load/vemem-rand2=2  load/vemem-rand3=5  load/kmsg-rand=0  
### wb_deferred_delta
base/probe=0  base/t-d0=0  base/t-d4=0  base/t-d12=0  base/t-rand=0  base/burst1=0  base/burst2=0  base/burst3=0  base/burst4=0  load/ve-d4=0  load/ve-rand=0  load/mem-d4=0  load/mem-rand=0  load/vemem-rand=0  load/vemem-rand2=0  load/vemem-rand3=0  load/kmsg-rand=0  
### wb_replaced_delta
base/probe=0  base/t-d0=0  base/t-d4=0  base/t-d12=0  base/t-rand=0  base/burst1=0  base/burst2=0  base/burst3=0  base/burst4=0  load/ve-d4=0  load/ve-rand=0  load/mem-d4=0  load/mem-rand=0  load/vemem-rand=1  load/vemem-rand2=2  load/vemem-rand3=4  load/kmsg-rand=0  
### wb_fail_error_delta
base/probe=0  base/t-d0=0  base/t-d4=0  base/t-d12=0  base/t-rand=0  base/burst1=0  base/burst2=0  base/burst3=0  base/burst4=0  load/ve-d4=1  load/ve-rand=0  load/mem-d4=0  load/mem-rand=0  load/vemem-rand=0  load/vemem-rand2=0  load/vemem-rand3=0  load/kmsg-rand=0  
### wb_fail_missed_delta
base/probe=0  base/t-d0=0  base/t-d4=0  base/t-d12=0  base/t-rand=0  base/burst1=0  base/burst2=0  base/burst3=0  base/burst4=0  load/ve-d4=0  load/ve-rand=0  load/mem-d4=0  load/mem-rand=0  load/vemem-rand=0  load/vemem-rand2=0  load/vemem-rand3=0  load/kmsg-rand=0  
### wb_fail_timeout_delta
base/probe=0  base/t-d0=0  base/t-d4=0  base/t-d12=0  base/t-rand=0  base/burst1=0  base/burst2=0  base/burst3=0  base/burst4=0  load/ve-d4=0  load/ve-rand=0  load/mem-d4=0  load/mem-rand=0  load/vemem-rand=0  load/vemem-rand2=0  load/vemem-rand3=0  load/kmsg-rand=0  
### wb_fail_cancelled_delta
base/probe=0  base/t-d0=0  base/t-d4=0  base/t-d12=0  base/t-rand=0  base/burst1=0  base/burst2=0  base/burst3=0  base/burst4=0  load/ve-d4=0  load/ve-rand=0  load/mem-d4=0  load/mem-rand=0  load/vemem-rand=0  load/vemem-rand2=0  load/vemem-rand3=0  load/kmsg-rand=0  
### client_fail_error
base/t-d0=0  base/t-d4=0  base/t-d12=0  base/t-rand=0  base/burst1=0  base/burst2=0  base/burst3=0  base/burst4=0  load/ve-d4=1  load/ve-rand=0  load/mem-d4=0  load/mem-rand=0  load/vemem-rand=0  load/vemem-rand2=0  load/vemem-rand3=0  load/kmsg-rand=0  
### client_fail_missed
base/t-d0=0  base/t-d4=0  base/t-d12=0  base/t-rand=0  base/burst1=0  base/burst2=0  base/burst3=0  base/burst4=0  load/ve-d4=0  load/ve-rand=0  load/mem-d4=0  load/mem-rand=0  load/vemem-rand=0  load/vemem-rand2=0  load/vemem-rand3=0  load/kmsg-rand=0  
### client_fail_replaced
base/t-d0=0  base/t-d4=0  base/t-d12=0  base/t-rand=0  base/burst1=0  base/burst2=0  base/burst3=0  base/burst4=0  load/ve-d4=0  load/ve-rand=0  load/mem-d4=0  load/mem-rand=0  load/vemem-rand=1  load/vemem-rand2=2  load/vemem-rand3=4  load/kmsg-rand=0  
### client_fail_timeout
base/t-d0=0  base/t-d4=0  base/t-d12=0  base/t-rand=0  base/burst1=0  base/burst2=0  base/burst3=0  base/burst4=0  load/ve-d4=0  load/ve-rand=0  load/mem-d4=0  load/mem-rand=0  load/vemem-rand=0  load/vemem-rand2=0  load/vemem-rand3=0  load/kmsg-rand=0  
### client_fail_cancelled
base/t-d0=0  base/t-d4=0  base/t-d12=0  base/t-rand=0  base/burst1=0  base/burst2=0  base/burst3=0  base/burst4=0  load/ve-d4=0  load/ve-rand=0  load/mem-d4=0  load/mem-rand=0  load/vemem-rand=0  load/vemem-rand2=0  load/vemem-rand3=0  load/kmsg-rand=0  
### acct_unexplained
base/t-d0=0  base/t-d4=0  base/t-d12=0  base/t-rand=0  base/burst1=0  base/burst2=0  base/burst3=0  base/burst4=0  load/ve-d4=0  load/ve-rand=0  load/mem-d4=0  load/mem-rand=0  load/vemem-rand=0  load/vemem-rand2=0  load/vemem-rand3=0  load/kmsg-rand=0  
### acct_gap_flips
base/t-d0=0  base/t-d4=0  base/t-d12=0  base/t-rand=0  base/burst1=0  base/burst2=0  base/burst3=0  base/burst4=0  load/ve-d4=77  load/ve-rand=152  load/mem-d4=48  load/mem-rand=50  load/vemem-rand=150  load/vemem-rand2=140  load/vemem-rand3=135  load/kmsg-rand=0  
### acct_gap_vblanks
base/t-d0=0  base/t-d4=0  base/t-d12=0  base/t-rand=0  base/burst1=0  base/burst2=0  base/burst3=0  base/burst4=0  load/ve-d4=77  load/ve-rand=152  load/mem-d4=61  load/mem-rand=68  load/vemem-rand=150  load/vemem-rand2=142  load/vemem-rand3=136  load/kmsg-rand=0  
### acct_late_vblanks
base/t-d0=0  base/t-d4=0  base/t-d12=0  base/t-rand=0  base/burst1=0  base/burst2=0  base/burst3=0  base/burst4=0  load/ve-d4=77  load/ve-rand=152  load/mem-d4=61  load/mem-rand=68  load/vemem-rand=150  load/vemem-rand2=140  load/vemem-rand3=135  load/kmsg-rand=0  
### acct_deferred_vblanks
base/t-d0=0  base/t-d4=0  base/t-d12=0  base/t-rand=0  base/burst1=0  base/burst2=0  base/burst3=0  base/burst4=0  load/ve-d4=0  load/ve-rand=0  load/mem-d4=0  load/mem-rand=0  load/vemem-rand=0  load/vemem-rand2=2  load/vemem-rand3=1  load/kmsg-rand=0  
### acct_client_late
base/t-d0=0  base/t-d4=0  base/t-d12=0  base/t-rand=0  base/burst1=0  base/burst2=0  base/burst3=0  base/burst4=0  load/ve-d4=40  load/ve-rand=108  load/mem-d4=45  load/mem-rand=48  load/vemem-rand=100  load/vemem-rand2=90  load/vemem-rand3=85  load/kmsg-rand=0  
### acct_commit_slow
base/t-d0=0  base/t-d4=0  base/t-d12=0  base/t-rand=0  base/burst1=0  base/burst2=0  base/burst3=0  base/burst4=0  load/ve-d4=37  load/ve-rand=44  load/mem-d4=3  load/mem-rand=2  load/vemem-rand=50  load/vemem-rand2=50  load/vemem-rand3=50  load/kmsg-rand=0  
### snapshot_latency_mean_ms
base/t-d0=0.291  base/t-d4=0.279  base/t-d12=0.282  base/t-rand=0.278  base/burst1=0.278  base/burst2=0.278  base/burst3=0.280  base/burst4=0.281  load/ve-d4=0.894  load/ve-rand=0.938  load/mem-d4=0.422  load/mem-rand=0.425  load/vemem-rand=0.989  load/vemem-rand2=0.972  load/vemem-rand3=0.934  load/kmsg-rand=0.260  
### snapshot_latency_max_ms
base/t-d0=2.471  base/t-d4=0.346  base/t-d12=2.303  base/t-rand=0.400  base/burst1=0.342  base/burst2=0.331  base/burst3=0.331  base/burst4=0.342  load/ve-d4=4.041  load/ve-rand=6.829  load/mem-d4=5.080  load/mem-rand=12.831  load/vemem-rand=5.350  load/vemem-rand2=5.750  load/vemem-rand3=4.294  load/kmsg-rand=0.523  
### ve_irqs_delta
base/probe=0  base/t-d0=0  base/t-d4=0  base/t-d12=0  base/t-rand=0  base/burst1=0  base/burst2=0  base/burst3=0  base/burst4=0  load/ve-d4=542  load/ve-rand=574  load/mem-d4=0  load/mem-rand=0  load/vemem-rand=580  load/vemem-rand2=568  load/vemem-rand3=562  load/kmsg-rand=0  
## Fence errors (L runs)
RESULT tear flips 600 frames_checked 600 ok 600 wrong 0 stale 0 early 0 mixed 0 bad 0 fence_errors 0
RESULT tear flips 600 frames_checked 600 ok 600 wrong 0 stale 0 early 0 mixed 0 bad 0 fence_errors 0
RESULT tear flips 600 frames_checked 600 ok 600 wrong 0 stale 0 early 0 mixed 0 bad 0 fence_errors 0
RESULT flip 593 fence_error status=-5 reason error
RESULT tear flips 600 frames_checked 599 ok 599 wrong 0 stale 0 early 0 mixed 0 bad 0 fence_errors 1
RESULT flip 51 fence_error status=-116 reason replaced
RESULT flip 441 fence_error status=-116 reason replaced
RESULT tear flips 600 frames_checked 598 ok 598 wrong 0 stale 0 early 0 mixed 0 bad 0 fence_errors 2
RESULT flip 399 fence_error status=-116 reason replaced
RESULT tear flips 600 frames_checked 599 ok 599 wrong 0 stale 0 early 0 mixed 0 bad 0 fence_errors 1
RESULT tear flips 600 frames_checked 600 ok 600 wrong 0 stale 0 early 0 mixed 0 bad 0 fence_errors 0
RESULT flip 180 fence_error status=-116 reason replaced
