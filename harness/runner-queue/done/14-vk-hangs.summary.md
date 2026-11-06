# 14-vk-hangs summary
Verdict: ran to completion (10/10 chunks, all ROUND-DONE, all CHUNK-RC 0). Kernel c38 (76bd27766): uname -v '#38 SMP PREEMPT Fri Nov  6 10:29:47 UTC 2026'. Start ~2026-11-06 10:38, end 11:01:17; stock kernel restored.
## Check 1 (PASS)
2026-11-06 10:38:44 fork: dc7266d584b (contains b7a705442bd), lib c439037226760ad38e2a39bf0a38c565; kernel c38 (76bd27766, Image md5 f7fc82bd55173cf0ddd56a15ff9a72d6)
2026-11-06 10:40:30 kernel fix: present (c38 contains e544ddb00)
kernel: #38 SMP PREEMPT Fri Nov  6 10:29:47 UTC 2026
2026-11-06 10:40:51 deployed vk1 ok (libvulkan_panfrost md5 6a7431597d2f374821a6b08dc9ff297d)
usage: see source
2026-11-06 11:01:17 restored: 7.3.1-edge-sunxi64 #17 SMP PREEMPT Fri Oct 30 12:09:52 UTC 2026 vmlinuz-7.3.1-edge-sunxi64 
## Check 2 diag: FAIL-DIAG (24 fork-* lines; not OK = fork-d2-ballot-*, fork-d3-elect-*, fork-d7-vote-*, fork-d8-cts-elect-* (x3 sizes each = 12), rc=134 excs 1x0x51 'Incomplete job or timeout', DMESG: js fault, js=1, status=INSTR_INVALID_ENC, head=0x12b20080, tail=0x12b20080). fork-d1,d4,d5,d6 OK (12 lines). sys-*: d2,d3,d6 fault as expected (data).
```
DIAG fork-d1-plain-1x1x1 rc=0 excs=[1x0x1 ] out=[1000 1000 1000 1000 1000 1000 1000 1000 1000 1000 1000 1000 1000 1000 1000 1000] wait=[dispatch 4 2 2: wait -> 0]
DIAG fork-d1-plain-4x1x1 rc=0 excs=[1x0x1 ] out=[1000 1001 1002 1003 1000 1001 1002 1003 1000 1001 1002 1003 1000 1001 1002 1003] wait=[dispatch 4 2 2: wait -> 0]
DIAG fork-d1-plain-3x5x7 rc=0 excs=[1x0x1 ] out=[1000 1001 1002 1000 1001 1002 1000 1001 1002 1000 1001 1002 1003 1004 1005 1003] wait=[dispatch 4 2 2: wait -> 0]
DIAG fork-d2-ballot-1x1x1 rc=134 excs=[1x0x51 ] out=[Incomplete job or timeout] wait=[]
DIAG fork-d2-ballot-4x1x1 rc=134 excs=[1x0x51 ] out=[Incomplete job or timeout] wait=[]
DIAG fork-d2-ballot-3x5x7 rc=134 excs=[1x0x51 ] out=[Incomplete job or timeout] wait=[]
DIAG fork-d3-elect-1x1x1 rc=134 excs=[1x0x51 ] out=[Incomplete job or timeout] wait=[]
DIAG fork-d3-elect-4x1x1 rc=134 excs=[1x0x51 ] out=[Incomplete job or timeout] wait=[]
DIAG fork-d3-elect-3x5x7 rc=134 excs=[1x0x51 ] out=[Incomplete job or timeout] wait=[]
DIAG fork-d4-shared-1x1x1 rc=0 excs=[1x0x1 ] out=[1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1] wait=[dispatch 4 2 2: wait -> 0]
DIAG fork-d4-shared-4x1x1 rc=0 excs=[1x0x1 ] out=[4 4 4 4 4 4 4 4 4 4 4 4 4 4 4 4] wait=[dispatch 4 2 2: wait -> 0]
DIAG fork-d4-shared-3x5x7 rc=0 excs=[1x0x1 ] out=[4 4 4 4 4 4 4 4 4 4 4 4 4 4 4 4] wait=[dispatch 4 2 2: wait -> 0]
DIAG fork-d5-ids-1x1x1 rc=0 excs=[1x0x1 ] out=[262144 262144 262144 262144 262144 262144 262144 262144 262144 262144 262144 262] wait=[dispatch 4 2 2: wait -> 0]
DIAG fork-d5-ids-4x1x1 rc=0 excs=[1x0x1 ] out=[262144 262145 262146 262147 262144 262145 262146 262147 262144 262145 262146 262] wait=[dispatch 4 2 2: wait -> 0]
DIAG fork-d5-ids-3x5x7 rc=0 excs=[1x0x1 ] out=[262144 262145 262146 262144 262145 262146 262144 262145 262146 262144 262145 262] wait=[dispatch 4 2 2: wait -> 0]
DIAG fork-d6-broadcast-1x1x1 rc=0 excs=[1x0x1 ] out=[256 256 256 256 256 256 256 256 256 256 256 256 256 256 256 256] wait=[dispatch 4 2 2: wait -> 0]
DIAG fork-d6-broadcast-4x1x1 rc=0 excs=[1x0x1 ] out=[260 260 260 260 260 260 260 260 260 260 260 260 260 260 260 260] wait=[dispatch 4 2 2: wait -> 0]
DIAG fork-d6-broadcast-3x5x7 rc=0 excs=[1x0x1 ] out=[260 260 260 260 260 260 260 260 260 260 260 260 260 260 260 260] wait=[dispatch 4 2 2: wait -> 0]
DIAG fork-d7-vote-1x1x1 rc=134 excs=[1x0x51 ] out=[Incomplete job or timeout] wait=[]
DIAG fork-d7-vote-4x1x1 rc=134 excs=[1x0x51 ] out=[Incomplete job or timeout] wait=[]
DIAG fork-d7-vote-3x5x7 rc=134 excs=[1x0x51 ] out=[Incomplete job or timeout] wait=[]
DIAG fork-d8-cts-elect-1x1x1 rc=134 excs=[1x0x51 ] out=[Incomplete job or timeout] wait=[]
DIAG fork-d8-cts-elect-4x1x1 rc=134 excs=[1x0x51 ] out=[Incomplete job or timeout] wait=[]
DIAG fork-d8-cts-elect-3x5x7 rc=134 excs=[1x0x51 ] out=[Incomplete job or timeout] wait=[]
DIAG sys-d1-plain-1x1x1 rc=0 excs=[1x0x1 ] out=[1000 1000 1000 1000 1000 1000 1000 1000 1000 1000 1000 1000 1000 1000 1000 1000] wait=[dispatch 4 2 2: wait -> 0]
DIAG sys-d1-plain-4x1x1 rc=0 excs=[1x0x1 ] out=[1000 1001 1002 1003 1000 1001 1002 1003 1000 1001 1002 1003 1000 1001 1002 1003] wait=[dispatch 4 2 2: wait -> 0]
DIAG sys-d1-plain-3x5x7 rc=0 excs=[1x0x1 ] out=[1000 1001 1002 1000 1001 1002 1000 1001 1002 1000 1001 1002 1003 1004 1005 1003] wait=[dispatch 4 2 2: wait -> 0]
DIAG sys-d2-ballot-1x1x1 rc=134 excs=[1x0x51 ] out=[Incomplete job or timeout] wait=[]
DIAG sys-d2-ballot-4x1x1 rc=134 excs=[1x0x51 ] out=[Incomplete job or timeout] wait=[]
DIAG sys-d2-ballot-3x5x7 rc=134 excs=[1x0x51 ] out=[Incomplete job or timeout] wait=[]
DIAG sys-d3-elect-1x1x1 rc=134 excs=[1x0x51 ] out=[Incomplete job or timeout] wait=[]
DIAG sys-d3-elect-4x1x1 rc=134 excs=[1x0x51 ] out=[Incomplete job or timeout] wait=[]
DIAG sys-d3-elect-3x5x7 rc=134 excs=[1x0x51 ] out=[Incomplete job or timeout] wait=[]
DIAG sys-d6-broadcast-1x1x1 rc=134 excs=[1x0x51 ] out=[Incomplete job or timeout] wait=[]
DIAG sys-d6-broadcast-4x1x1 rc=134 excs=[1x0x51 ] out=[Incomplete job or timeout] wait=[]
DIAG sys-d6-broadcast-3x5x7 rc=134 excs=[1x0x51 ] out=[Incomplete job or timeout] wait=[]
```
DMESG lines:
DMESG fork-d2-ballot-1x1x1: [   67.588626] panfrost 1800000.gpu: js fault, js=1, status=INSTR_INVALID_ENC, head=0x12b20080, tail=0x12b20080
DMESG fork-d2-ballot-4x1x1: [   67.859768] panfrost 1800000.gpu: js fault, js=1, status=INSTR_INVALID_ENC, head=0x12b20080, tail=0x12b20080
DMESG fork-d2-ballot-3x5x7: [   68.093843] panfrost 1800000.gpu: js fault, js=1, status=INSTR_INVALID_ENC, head=0x12b20080, tail=0x12b20080
DMESG fork-d3-elect-1x1x1: [   68.327952] panfrost 1800000.gpu: js fault, js=1, status=INSTR_INVALID_ENC, head=0x12b20080, tail=0x12b20080
DMESG fork-d3-elect-4x1x1: [   68.561846] panfrost 1800000.gpu: js fault, js=1, status=INSTR_INVALID_ENC, head=0x12b20080, tail=0x12b20080
DMESG fork-d3-elect-3x5x7: [   68.803950] panfrost 1800000.gpu: js fault, js=1, status=INSTR_INVALID_ENC, head=0x12b20080, tail=0x12b20080
DMESG fork-d7-vote-1x1x1: [   71.155177] panfrost 1800000.gpu: js fault, js=1, status=INSTR_INVALID_ENC, head=0x12b20080, tail=0x12b20080
DMESG fork-d7-vote-4x1x1: [   71.391078] panfrost 1800000.gpu: js fault, js=1, status=INSTR_INVALID_ENC, head=0x12b20080, tail=0x12b20080
DMESG fork-d7-vote-3x5x7: [   71.628613] panfrost 1800000.gpu: js fault, js=1, status=INSTR_INVALID_ENC, head=0x12b20080, tail=0x12b20080
DMESG fork-d8-cts-elect-1x1x1: [   71.871775] panfrost 1800000.gpu: js fault, js=1, status=INSTR_INVALID_ENC, head=0x12b20080, tail=0x12b20080
DMESG fork-d8-cts-elect-4x1x1: [   72.113048] panfrost 1800000.gpu: js fault, js=1, status=INSTR_INVALID_ENC, head=0x12b20080, tail=0x12b20080
DMESG fork-d8-cts-elect-3x5x7: [   72.356327] panfrost 1800000.gpu: js fault, js=1, status=INSTR_INVALID_ENC, head=0x12b20080, tail=0x12b20080
## Check 3 cases-sg / Check 4 frag
```
CASE dEQP-VK.subgroups.basic.compute.subgroupelect rc=134 t=3s result=[] msg=[Incomplete job or timeout]
CASE dEQP-VK.subgroups.basic.compute.subgroupelect_requiredsubgroupsize rc=0 t=0s result=[ NotSupported (VK_EXT_subgroup_size_control is not supported at vktTestCase.cpp:1394)] msg=[]
CASE dEQP-VK.subgroups.basic.graphics.subgroupelect rc=134 t=1s result=[] msg=[Incomplete job or timeout]
CASE dEQP-VK.subgroups.ballot_broadcast.compute.subgroupbroadcast_int8_t rc=0 t=0s result=[ NotSupported (Device does not support the specified format in subgroup operations at vktSubgroupsBallotBroadcastTests.cpp:273)] msg=[]
CASE dEQP-VK.subgroups.ballot_broadcast.compute.subgroupbroadcast_uint rc=134 t=2s result=[] msg=[Incomplete job or timeout]
CASE dEQP-VK.subgroups.basic.compute.subgroupbarrier rc=134 t=1s result=[] msg=[Incomplete job or timeout]
CASE dEQP-VK.subgroups.builtin_var.compute.subgroupsize_compute rc=0 t=2s result=[ Pass (OK)] msg=[]
CASE dEQP-VK.spirv_assembly.type.vec4.i8.clamp_frag rc=0 t=4s result=[ Pass (Rendered output matches input)] msg=[]
CASE dEQP-VK.spirv_assembly.type.vec4.u32.bit_field_insert_offset16_count16_frag rc=0 t=4s result=[ Pass (Rendered output matches input)] msg=[]
CASE dEQP-VK.spirv_assembly.type.vec4.i16.bit_field_insert_offset8_count16_frag rc=0 t=4s result=[ Pass (Rendered output matches input)] msg=[]
CASE dEQP-VK.spirv_assembly.type.vec4.u16.bit_field_insert_offset8_count16_frag rc=0 t=4s result=[ Pass (Rendered output matches input)] msg=[]
CASE dEQP-VK.spirv_assembly.type.vec4.i8.bit_field_insert_offset16_count64_frag rc=0 t=4s result=[ Pass (Rendered output matches input)] msg=[]
CASE dEQP-VK.spirv_assembly.type.vec4.i64.bit_field_u_extract_offset8_count16_frag rc=0 t=4s result=[ Pass (Rendered output matches input)] msg=[]
CASE dEQP-VK.spirv_assembly.type.vec4.u64.bit_field_insert_offset8_count64_frag rc=0 t=5s result=[ Pass (Rendered output matches input)] msg=[]
```
Check 3: subgroupelect, subgroupelect(graphics), subgroupbroadcast_uint, subgroupbarrier FAIL (Incomplete job or timeout); subgroupelect_requiredsubgroupsize and subgroupbroadcast_int8_t NotSupported; subgroupsize_compute PASS.
Check 4: all 7 frag cases PASS (t=4s,4s,4s,4s,4s,4s,5s); no 'gpu sched timeout' (0).
## Check 5 subset: PASS (REGRESSIONS: 0); SUBSET-COMPLETE
```
NEW cases 5225: Crash=12 Fail=2 NotSupported=1847 Pass=3364
REGRESSIONS: 0
FIXED: 4
  FIX dEQP-VK.subgroups.basic.framebuffer.subgroupbarrier_fragment (was OOM)
  FIX dEQP-VK.subgroups.basic.framebuffer.subgroupmemorybarrier_fragment (was OOM)
  FIX dEQP-VK.subgroups.basic.framebuffer.subgroupmemorybarrierbuffer_fragment (was OOM)
  FIX dEQP-VK.subgroups.basic.framebuffer.subgroupmemorybarrierimage_fragment (was OOM)
STILL-NONPASS: 14
  STILL dEQP-VK.api.device_init.create_device_global_priority.basic Fail (was Fail)
  STILL dEQP-VK.api.device_init.create_device_global_priority_khr.basic Fail (was Fail)
  STILL dEQP-VK.subgroups.basic.compute.subgroupbarrier Crash (was OOM)
  STILL dEQP-VK.subgroups.basic.compute.subgroupelect Crash (was OOM)
  STILL dEQP-VK.subgroups.basic.compute.subgroupmemorybarrier Crash (was OOM)
  STILL dEQP-VK.subgroups.basic.compute.subgroupmemorybarrierbuffer Crash (was OOM)
  STILL dEQP-VK.subgroups.basic.compute.subgroupmemorybarrierimage Crash (was OOM)
  STILL dEQP-VK.subgroups.basic.compute.subgroupmemorybarriershared Crash (was OOM)
  STILL dEQP-VK.subgroups.basic.graphics.subgroupbarrier Crash (was OOM)
  STILL dEQP-VK.subgroups.basic.graphics.subgroupelect Crash (was OOM)
  STILL dEQP-VK.subgroups.basic.graphics.subgroupmemorybarrier Crash (was OOM)
  STILL dEQP-VK.subgroups.basic.graphics.subgroupmemorybarrierbuffer Crash (was OOM)
  STILL dEQP-VK.subgroups.basic.graphics.subgroupmemorybarrierimage Crash (was OOM)
  STILL dEQP-VK.subgroups.clustered.graphics.subgroupclusteredmul_ivec4 Crash (was OOM)
MISSING (in baseline, not run): 0
```
## Check 6 ocl: PASS
```
Compute Info,Pass,0,PASSED 3 of 3 tests.,15,computeinfo/test_computeinfo
Relationals,Pass,0,PASSED 17 of 17 tests.,684,relationals/test_relationals
Atomics,Pass,0,PASSED 13 of 13 tests.,5,atomics/test_atomics
Select,Pass,0,PASSED 22 of 22 tests.,14,select/test_select -w
Half Ops,Pass,0,PASSED 13 of 13 tests.,67,half/test_half -w
C11 Atomics,Pass,0,PASSED 32 of 32 tests.,15,c11_atomics/test_c11_atomics
Workgroups,Pass,0,,1,workgroups/test_workgroups
Subgroups,Pass,0,,1,subgroups/test_subgroups
```
## Check 7 gles: PASS
caselist /root/vkhangs/gles3-derivate.txt, 556 cases, 12 s
Pass                   556
## Check 8 dmesg (hits of js fault|Soft-stop failed|Page fault|Unhandled / gpu sched timeout / js fault)
- dmesg-cases-frag-a.txt hit=0 sched=0 js=0
- dmesg-cases-frag-b.txt hit=0 sched=0 js=0
- dmesg-cases-sg.txt hit=8 sched=0 js=8
- dmesg-diag.txt hit=42 sched=0 js=42
- dmesg-gles.txt hit=0 sched=0 js=0
- dmesg-ocl.txt hit=0 sched=0 js=0
- dmesg-subset1.txt hit=12 sched=0 js=12
- dmesg-subset2.txt hit=0 sched=0 js=0
- dmesg-subset3.txt hit=0 sched=0 js=0
- dmesg-subset4.txt hit=0 sched=0 js=0
Check 8 verdict: subset1 has 12 hits => FAIL for subset (js fault lines above); ocl, gles, subset2-4 PASS (0). diag/cases hits are expected.
## Check 9: PASS, all chunks end ROUND-DONE.
## State
diag
cases-sg
cases-frag-a
cases-frag-b
subset1
subset2
subset3
subset4
ocl
gles
Files: harness/research/vk-hangs/logs/runner/
