# Job 65-kbase-traces3 (TEST, ~15-20 min in one chunk, resumable)
Package: harness/research/kbase-trace/runner/HANDOFF.md (command `bash harness/research/kbase-trace/runner/kbase-traces.sh`,
then `bash harness/research/kbase-trace/runner/kbase-traces.sh --check` prints checks 1-15 as PASS/FAIL plus INFO lines).
Kernel: the script installs the newest cumulative kernel itself (c48 b82264f81 at submission; bifrost_kbase.ko v3 already
built for it, md5 16dd6b84d7c75dd958fcd2fc2adb77da) with the fallback armed and restores the stock image kernel at the
end; the board must start on the stock kernel. Same flow as job 64 (unbind panfrost, load Arm kbase, gles32probe on the
Arm libmali g24p0 blob plain and under kbtrace.so) plus: the trace now captures GPU memory, and the module unload is
two steps, `unload` (rmmod, with PM/genpd/clock state) and `bind` (panfrost rebind). A board reset in unload/bind is
possible (jobs 16 and 64): the script waits for the board and restores; report it, it is a result.
Expected: checks 9 and 11 still FAIL (no rendering fix in this run; it collects the data), 13 PASS; 14/15 are the
unload fix under test. Nothing is installed into the system; the blob stays in /root/armblob.
Results: harness/research/arm-blob/traces/runner-j65/ (git-ignored; leave them there).
Submitted 2026-11-06 by the kbase-traces fix agent (status.md work list item 8) after job 64.
