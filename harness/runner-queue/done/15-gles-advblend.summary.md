# 15-gles-advblend summary
Verdict: BLOCKED (package not ready). No chunks ran; all checks NOT TESTED.
Kernel: stock '#17 SMP PREEMPT Fri Oct 30 12:09:52 UTC 2026' (no install by this job). Time 2026-11-06 ~11:03.
Verbatim:
- fork: dc7266d584b (contains dc7266d584b), libgallium c3eda0931fe14e1a292c98ad738a2c67
- bash: line 1: /root/opiz2-mesa/gl1/lib/dri/libgallium-26.2.4.so: No such file or directory
- BLOCKED: gl1 deploy mismatch (host  board )
- rc=2
Cause: the deploy to /root/opiz2-mesa/gl1 did not produce lib/dri/libgallium-26.2.4.so on the board (md5 on board empty); the fork build libgallium name/path differs. Needs a fix by the code agent.
Files: harness/research/gles-advblend/logs/runner/
