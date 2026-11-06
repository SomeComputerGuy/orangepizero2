# Job 52-gpu-invalid-enc summary
Kernel (uname -v): #38 SMP PREEMPT Fri Nov  6 10:29:47 UTC 2026 (c38); restored: 7.3.1-edge-sunxi64 #17. Start 2026-11-06 15:49, end 16:13. Verdict: ALL PASS (checks 1-9).

## 1 (PASS)
2026-11-06 15:49:18 fork: 0e274280595 (contains 0e274280595), lib 9eaa0909212745209447e008dfcbcd24; kernel c38 (76bd27766, Image md5 f7fc82bd55173cf0ddd56a15ff9a72d6)
2026-11-06 15:49:52 fork: 0e274280595 (contains 0e274280595), lib 9eaa0909212745209447e008dfcbcd24; kernel c38 (76bd27766, Image md5 f7fc82bd55173cf0ddd56a15ff9a72d6)
2026-11-06 15:51:43 kernel fix: present (c38 contains e544ddb00)
kernel: #38 SMP PREEMPT Fri Nov  6 10:29:47 UTC 2026
2026-11-06 15:52:06 deployed vk2 ok (libvulkan_panfrost md5 1b0a525bf415ba6cdbf15373e2afa86e)
usage: see source
2026-11-06 16:13:08 restored: 7.3.1-edge-sunxi64 #17 SMP PREEMPT Fri Oct 30 12:09:52 UTC 2026 vmlinuz-7.3.1-edge-sunxi64 

## 2a PASS (24/24 rc=0, excs only x0x1), 2b PASS (d1/d4/d5/d6 identical to job 14; ballot 1/15, elect 42 / 42 13 13 13, vote 7/5)
DIAG fork-d1-plain-1x1x1 rc=0 excs=[1x0x1 ] out=[1000 1000 1000 1000 1000 1000 1000 1000 1000 1000 1000 1000 1000 1000 1000 1000] wait=[dispatch 4 2 2: wait -> 0]
DIAG fork-d1-plain-4x1x1 rc=0 excs=[1x0x1 ] out=[1000 1001 1002 1003 1000 1001 1002 1003 1000 1001 1002 1003 1000 1001 1002 1003] wait=[dispatch 4 2 2: wait -> 0]
DIAG fork-d1-plain-3x5x7 rc=0 excs=[1x0x1 ] out=[1000 1001 1002 1000 1001 1002 1000 1001 1002 1000 1001 1002 1003 1004 1005 1003] wait=[dispatch 4 2 2: wait -> 0]
DIAG fork-d2-ballot-1x1x1 rc=0 excs=[1x0x1 ] out=[1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1] wait=[dispatch 4 2 2: wait -> 0]
DIAG fork-d2-ballot-4x1x1 rc=0 excs=[1x0x1 ] out=[15 15 15 15 15 15 15 15 15 15 15 15 15 15 15 15] wait=[dispatch 4 2 2: wait -> 0]
DIAG fork-d2-ballot-3x5x7 rc=0 excs=[1x0x1 ] out=[15 15 15 15 15 15 15 15 15 15 15 15 15 15 15 15] wait=[dispatch 4 2 2: wait -> 0]
DIAG fork-d3-elect-1x1x1 rc=0 excs=[1x0x1 ] out=[42 42 42 42 42 42 42 42 42 42 42 42 42 42 42 42] wait=[dispatch 4 2 2: wait -> 0]
DIAG fork-d3-elect-4x1x1 rc=0 excs=[1x0x1 ] out=[42 13 13 13 42 13 13 13 42 13 13 13 42 13 13 13] wait=[dispatch 4 2 2: wait -> 0]
DIAG fork-d3-elect-3x5x7 rc=0 excs=[1x0x1 ] out=[42 13 13 42 13 13 42 13 13 42 13 13 13 42 13 13] wait=[dispatch 4 2 2: wait -> 0]
DIAG fork-d4-shared-1x1x1 rc=0 excs=[1x0x1 ] out=[1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1] wait=[dispatch 4 2 2: wait -> 0]
DIAG fork-d4-shared-4x1x1 rc=0 excs=[1x0x1 ] out=[4 4 4 4 4 4 4 4 4 4 4 4 4 4 4 4] wait=[dispatch 4 2 2: wait -> 0]
DIAG fork-d4-shared-3x5x7 rc=0 excs=[1x0x1 ] out=[4 4 4 4 4 4 4 4 4 4 4 4 4 4 4 4] wait=[dispatch 4 2 2: wait -> 0]
DIAG fork-d5-ids-1x1x1 rc=0 excs=[1x0x1 ] out=[262144 262144 262144 262144 262144 262144 262144 262144 262144 262144 262144 262] wait=[dispatch 4 2 2: wait -> 0]
DIAG fork-d5-ids-4x1x1 rc=0 excs=[1x0x1 ] out=[262144 262145 262146 262147 262144 262145 262146 262147 262144 262145 262146 262] wait=[dispatch 4 2 2: wait -> 0]
DIAG fork-d5-ids-3x5x7 rc=0 excs=[1x0x1 ] out=[262144 262145 262146 262144 262145 262146 262144 262145 262146 262144 262145 262] wait=[dispatch 4 2 2: wait -> 0]
DIAG fork-d6-broadcast-1x1x1 rc=0 excs=[1x0x1 ] out=[256 256 256 256 256 256 256 256 256 256 256 256 256 256 256 256] wait=[dispatch 4 2 2: wait -> 0]
DIAG fork-d6-broadcast-4x1x1 rc=0 excs=[1x0x1 ] out=[260 260 260 260 260 260 260 260 260 260 260 260 260 260 260 260] wait=[dispatch 4 2 2: wait -> 0]
DIAG fork-d6-broadcast-3x5x7 rc=0 excs=[1x0x1 ] out=[260 260 260 260 260 260 260 260 260 260 260 260 260 260 260 260] wait=[dispatch 4 2 2: wait -> 0]
DIAG fork-d7-vote-1x1x1 rc=0 excs=[1x0x1 ] out=[7 7 7 7 7 7 7 7 7 7 7 7 7 7 7 7] wait=[dispatch 4 2 2: wait -> 0]
DIAG fork-d7-vote-4x1x1 rc=0 excs=[1x0x1 ] out=[5 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5] wait=[dispatch 4 2 2: wait -> 0]
DIAG fork-d7-vote-3x5x7 rc=0 excs=[1x0x1 ] out=[5 5 5 5 5 5 5 5 5 5 5 5 5 5 5 5] wait=[dispatch 4 2 2: wait -> 0]
DIAG fork-d8-cts-elect-1x1x1 rc=0 excs=[1x0x1 ] out=[1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1] wait=[dispatch 4 2 2: wait -> 0]
DIAG fork-d8-cts-elect-4x1x1 rc=0 excs=[1x0x1 ] out=[1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1] wait=[dispatch 4 2 2: wait -> 0]
DIAG fork-d8-cts-elect-3x5x7 rc=0 excs=[1x0x1 ] out=[1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1] wait=[dispatch 4 2 2: wait -> 0]

## 3 PASS (9/9)
CASE dEQP-VK.subgroups.basic.compute.subgroupelect rc=0 t=2s result=[ Pass (OK)] msg=[]
CASE dEQP-VK.subgroups.basic.graphics.subgroupelect rc=0 t=1s result=[ Pass (OK)] msg=[]
CASE dEQP-VK.subgroups.ballot_broadcast.compute.subgroupbroadcast_uint rc=0 t=2s result=[ Pass (OK)] msg=[]
CASE dEQP-VK.subgroups.basic.compute.subgroupbarrier rc=0 t=1s result=[ Pass (OK)] msg=[]
CASE dEQP-VK.subgroups.basic.compute.subgroupmemorybarrier rc=0 t=1s result=[ Pass (OK)] msg=[]
CASE dEQP-VK.subgroups.basic.compute.subgroupmemorybarriershared rc=0 t=2s result=[ Pass (OK)] msg=[]
CASE dEQP-VK.subgroups.basic.graphics.subgroupbarrier rc=0 t=1s result=[ Pass (OK)] msg=[]
CASE dEQP-VK.subgroups.clustered.graphics.subgroupclusteredmul_ivec4 rc=0 t=2s result=[ Pass (OK)] msg=[]
CASE dEQP-VK.subgroups.builtin_var.compute.subgroupsize_compute rc=0 t=1s result=[ Pass (OK)] msg=[]

## 4 PASS
suite,verdict,exit,summary,seconds,command
Images (Samplerless int),Pass,0,PASSED 6 of 6 tests.,33,images/samplerlessReads/test_samplerless_reads int
Images (Samplerless uint),Pass,0,PASSED 6 of 6 tests.,18,images/samplerlessReads/test_samplerless_reads uint
Images (Samplerless float),Pass,0,PASSED 6 of 6 tests.,40,images/samplerlessReads/test_samplerless_reads float

## 5 5a PASS 5b PASS (subset1-4 identical, all SUBSET-COMPLETE)
NEW cases 5225: Fail=2 NotSupported=1847 Pass=3376
REGRESSIONS: 0
FIXED: 16
  FIX dEQP-VK.subgroups.basic.compute.subgroupbarrier (was OOM)
  FIX dEQP-VK.subgroups.basic.compute.subgroupelect (was OOM)
  FIX dEQP-VK.subgroups.basic.compute.subgroupmemorybarrier (was OOM)
  FIX dEQP-VK.subgroups.basic.compute.subgroupmemorybarrierbuffer (was OOM)
  FIX dEQP-VK.subgroups.basic.compute.subgroupmemorybarrierimage (was OOM)
  FIX dEQP-VK.subgroups.basic.compute.subgroupmemorybarriershared (was OOM)
  FIX dEQP-VK.subgroups.basic.framebuffer.subgroupbarrier_fragment (was OOM)
  FIX dEQP-VK.subgroups.basic.framebuffer.subgroupmemorybarrier_fragment (was OOM)
  FIX dEQP-VK.subgroups.basic.framebuffer.subgroupmemorybarrierbuffer_fragment (was OOM)
  FIX dEQP-VK.subgroups.basic.framebuffer.subgroupmemorybarrierimage_fragment (was OOM)
  FIX dEQP-VK.subgroups.basic.graphics.subgroupbarrier (was OOM)
  FIX dEQP-VK.subgroups.basic.graphics.subgroupelect (was OOM)
  FIX dEQP-VK.subgroups.basic.graphics.subgroupmemorybarrier (was OOM)
  FIX dEQP-VK.subgroups.basic.graphics.subgroupmemorybarrierbuffer (was OOM)
  FIX dEQP-VK.subgroups.basic.graphics.subgroupmemorybarrierimage (was OOM)
  FIX dEQP-VK.subgroups.clustered.graphics.subgroupclusteredmul_ivec4 (was OOM)
  STILL dEQP-VK.api.device_init.create_device_global_priority.basic Fail (was Fail)
  STILL dEQP-VK.api.device_init.create_device_global_priority_khr.basic Fail (was Fail)

## 6 PASS
suite,verdict,exit,summary,seconds,command
Compute Info,Pass,0,PASSED 3 of 3 tests.,3,computeinfo/test_computeinfo
Relationals,Pass,0,PASSED 17 of 17 tests.,698,relationals/test_relationals
Atomics,Pass,0,PASSED 13 of 13 tests.,5,atomics/test_atomics
Select,Pass,0,PASSED 22 of 22 tests.,14,select/test_select -w
Half Ops,Pass,0,PASSED 13 of 13 tests.,66,half/test_half -w
C11 Atomics,Pass,0,PASSED 32 of 32 tests.,16,c11_atomics/test_c11_atomics
Workgroups,Pass,0,,1,workgroups/test_workgroups
Subgroups,Pass,0,,3,subgroups/test_subgroups

## 7 PASS
caselist /root/invenc/gles3-derivate.txt, 556 cases, 12 s
Pass                   556

## 8 8a PASS 8b PASS (INSTR_INVALID_ENC / fault-pattern / gpu sched timeout per chunk)
dmesg-cases-sg.txt 0 0 0
dmesg-diag.txt 0 0 0
dmesg-gles.txt 0 0 0
dmesg-ocl.txt 0 0 0
dmesg-sl.txt 0 0 0
dmesg-subset1.txt 0 0 0
dmesg-subset2.txt 0 0 0
dmesg-subset3.txt 0 0 0
dmesg-subset4.txt 0 0 0

## 9 PASS: all 9 chunks end ROUND-DONE. State:
diag
cases-sg
sl
subset1
subset2
subset3
subset4
ocl
gles

Note: first launch was killed by me within seconds (wrongly wrapped in timeout) before any chunk ran; lock released, rerun clean. dmesg: nothing abnormal.
Results: harness/research/gpu-invalid-enc/logs/runner/
