# Job 67-kbase-traces5 (TEST, ~17 min in one chunk, resumable)
Package: harness/research/kbase-trace/runner/HANDOFF.md (command `bash harness/research/kbase-trace/runner/kbase-traces.sh`,
then `bash harness/research/kbase-trace/runner/kbase-traces.sh --check` prints checks 1-20 as PASS/FAIL plus INFO lines).
Kernel: the script installs the newest cumulative kernel itself (c48 b82264f81 at submission; bifrost_kbase.ko v4 already
built for it, md5 aa7e170386c6672fe001d95daff25f30) with the fallback armed and restores the stock image kernel at the
end; the board must start on the stock kernel. Same flow as job 66, but step `afbc` is replaced by step `fb`: the basic
case with three framebuffer modes of gles32probe (tex8 = control with AFBC, rgba16f, rgba32f = float colour buffers,
for which the blob uses no AFBC), then probe + trace with the first float mode that renders.
Expected: all PASS. tex8 showing 0 lit pixels and DATA_INVALID faults is the expected control. A board reset in
unload/bind is possible: the script waits for the board and restores; report it, it is a result. Nothing is installed
into the system.
Results: harness/research/arm-blob/traces/runner-j67/ (git-ignored; leave them there).
Submitted 2026-11-06 by the kbase-traces fix agent (status.md work list item 8) after job 66.
