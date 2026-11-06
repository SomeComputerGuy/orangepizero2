# Job 66-kbase-traces4 (TEST, ~17 min in one chunk, resumable)
Package: harness/research/kbase-trace/runner/HANDOFF.md (command `bash harness/research/kbase-trace/runner/kbase-traces.sh`,
then `bash harness/research/kbase-trace/runner/kbase-traces.sh --check` prints checks 1-19 as PASS/FAIL plus INFO lines).
Kernel: the script installs the newest cumulative kernel itself (c48 b82264f81 at submission; bifrost_kbase.ko v4 already
built for it, md5 aa7e170386c6672fe001d95daff25f30) with the fallback armed and restores the stock image kernel at the
end; the board must start on the stock kernel. Same flow as job 65 plus a new short step `afbc` before the probe: the
basic case under four Arm-blob config files (v0 control, v1-v3 AFBC off), then probe + trace under the first variant
that renders. Job 65 showed the fragment fault is the blob writing AFBC render targets on this AFBC-less G31.
Expected: all PASS (check 11 may still FAIL if some fault remains: report it). A board reset in unload/bind is
possible: the script waits for the board and restores; report it, it is a result. Nothing is installed into the system.
Results: harness/research/arm-blob/traces/runner-j66/ (git-ignored; leave them there).
Submitted 2026-11-06 by the kbase-traces fix agent (status.md work list item 8) after job 65.
