# 21-de33-writeback: BLOCKED (package not ready: kernel c24 lacks writeback)
Start 2026-11-06 01:27:19 UTC, end 01:32:43 UTC. Not a FAIL, no checks applicable.
BLOCKED (verbatim): kernel c24 has no Writeback-1 connector / de33_wb_* parameters (writeback not in this kernel)
Kernel: c24 (Image md5 3de93f5e0a45c26e1be069814cd313a7), uname -v: #23 SMP PREEMPT Fri Nov  6 00:46:05 UTC 2026
runner.log: 2026-11-06 01:32:43 restored: 7.3.1-edge-sunxi64 #17 SMP PREEMPT Fri Oct 30 12:09:52 UTC 2026 vmlinuz-7.3.1-edge-sunxi64
Needed: merge 6dbed6c18 (fix/sunxi-h616-de33-writeback) into test-cumulative and serve the next kernel.
Results: harness/research/de33-writeback/logs/runner-wb/
