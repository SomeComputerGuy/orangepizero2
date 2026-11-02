# PM round-4 board results (dbg v3 ed27bfae… u-boot-sunxi-with-spl-dbg.bin + full DTB 3fc9fadc…), 2026-11-02
Board left on dbg v3, knob mode 0 (default), systemd watchdog 15 s on. Traces: pm-trace-g1.txt, pm-trace-g2.txt (frozen rings, `h616-pm-regs.py --trace` output).

## G0 PASS
psci_idle registered; end0 up; CPUCFG 0x09010010 = 0x8f000000 (AArch64 bits 27:24 = f).
Oddity: after a warm reboot `--trace` printed "system ring: 47625 events" and listed SLEEP_* records for core0 after BOOT -> SLEEP events leak into the system ring or the decoder mislabels rings.

## G1 (--knob 1 = WAKE + GIC cpuif off) FAIL, but no more SPL/BROM (AArch64 fix works)
~3.5 min after knob (05:01:5x -> 05:04:47): RCU stall on CPU 1: "1-...!: (3 GPs behind) idle=ba98/0/0x0 softirq=3808/3808 fqs=0", detected by CPU3; NMI to CPU1 unanswered; then "rcu_preempt kthread timer wakeup didn't happen for 7757 jiffies ... Possible timer handling issue on cpu=0"; watchdog reset (gen 2).
Frozen rings (enter/wake/wfiret): core0 42/42/18 (last ENTER d0=0000aa01 d1=2, WAKE d0=aa d1=3); core1 23/23/0 but LAST record = SLEEP_ENTER d0=00004401 d1=00000000 at 159946.935 ms, no WAKE after -> gated, never woken (lost wakeup; PEND=0 at entry); core2 23/23/0 last WAKE d0=aa d1=6; core3 23/23/0 last WAKE d0=22 d1=a.
Hypotheses: IRQ/IPI arriving while gated or racing CORE_CLOSE+WFI lost with cpuif off (nIRQOUT vs nIRQ; PPI local timer vs broadcast timer for local-timer-stop). Check a broadcast clockevent is actually registered.

## G2 (--knob 2 = WAKE + cpuif on) FAIL
Silent hang ~20 s after knob (no RCU msg), watchdog reset (gen 3). Rings: core0 41/41/19, core1 21/21/4, core2 21/22/3, core3 23/23/0. Last: core1 ENTER d0=00004002 d1=0000000d then WFI_RET d0=40 d1=0f (last record); core0 ENTER d0=402 d1=0 then WAKE d0=4 d1=1; core3 ENTER d0=402 then WAKE; core2 WFI_RET then WAKE. No core obviously stuck in ENTER -> suspect the WFI_RET restart path.

## G3 full suspend (mode 0, watchdog off) resumes ON TIME
rtcwake 05:08:14 -> alarm 05:08:26 -> "Enabling non-boot CPUs" 05:08:26.995. System ring verbatim:
  SYS_SUSPEND d0=03000301 d1=ba003e00
  SYS_JUMP    d0=00000000 d1=00020000
  SYS_RESUME  d0=80aaaa03 d1=00000001
-> entry STATR=0xaa and exit STATR=0xaa, both timed out: controller never reports self-refresh with current request. Patch 2 SR request must be adapted.
