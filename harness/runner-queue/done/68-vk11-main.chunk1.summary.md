# 68-vk11-main chunk1: BLOCKED (exit 2), 0 of 64 parts
Start 2026-11-06 22:56, end 23:06. Kernel during run: #51 SMP PREEMPT Fri Nov 6 20:28:54 UTC 2026 (c48). After restore: 7.3.1-edge-sunxi64 #17 SMP PREEMPT Fri Oct 30 12:09:52 UTC 2026. Hand-overs 0, pauses 0.
Counts: Pass/Fail/Crash/Timeout/Hang = none finished (part-00 reached 4244 of 50743 cases, never completed); Hang rows 0.
BLOCKED: part-00: 3 rounds in a row without a new result. Rounds show DEQP-RC 143 and the memcg oom-killer (600 MB) killing deqp-vk at case 4244:
DMESG: [  403.947382] deqp-vk invoked oom-killer: gfp_mask=0x100cca(GFP_HIGHUSER_MOVABLE), order=0, oom_score_adj=1000
DMESG: [  403.948238] oom-kill:constraint=CONSTRAINT_MEMCG,nodemask=(null),cpuset=/,mems_allowed=0,oom_memcg=/system.slice/run-p10454-i10697.scope,task_memcg=/system.slice/run-p10454-i10697.scope,task=deqp-vk,pid=10458,uid=0

## --check
== job 68 checks (2026-11-06 23:06:32)
1 setup (fork ded6ccea0bc, vk3 deployed, kernel with e544ddb00): PASS
2 board apiVersion 1.1 + vkCreateDevice with all 1.1 features: PASS (apiVersion 1.1.354)
3 ARM core builtins probe d9 (rc=0, ids <= max, core count = shaderCoreCount 1): FAIL
4 subgroup probes d2/d3/d6/d8 = job 52 values: PASS
5 parts complete: 0 of 64: FAIL
6 every finished part has one row per case: PASS
7 INSTR_INVALID_ENC in dmesg: 0: PASS
8 GPU faults in dmesg (js fault 0, page/MMU fault 0, gpu sched timeout 0): PASS
9 regressions: no finished part yet: FAIL
INFO Hang rows (stall watchdog): 0 ; stalls: 0
INFO Soft-stop lines in dmesg: 0
INFO BLOCKED: part-00: 3 rounds in a row without a new result (see /home/aruni/orangepizero2/harness/research/vk11/logs/runner/files/part-00/round-*.txt)

No INSTR_INVALID_ENC / js fault / page fault / sched timeout lines in dmesg. Check 3 FAIL: d9 probe outputs contain 4294967295 values (see logs/runner/chunk-probe.txt).
Results: harness/research/vk11/logs/runner/ ; job file left in harness/runner-queue/.
