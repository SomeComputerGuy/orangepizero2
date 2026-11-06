# Job 64-kbase-traces2 (TEST, ~15 min in one chunk, resumable)
Package: harness/research/kbase-trace/runner/HANDOFF.md (command `bash harness/research/kbase-trace/runner/kbase-traces.sh`,
then `bash harness/research/kbase-trace/runner/kbase-traces.sh --check` prints checks 1-12 as PASS/FAIL plus INFO lines).
Kernel: the script installs the newest cumulative kernel itself (c48 b82264f81 at submission; kbase.ko already built for
it) with the fallback armed and restores the stock image kernel at the end; the board must start on the stock kernel.
It unbinds panfrost, loads the Arm kbase, runs gles32probe on the Arm libmali g24p0 blob plain (with kbase debugfs
sampling) and under the fixed kbtrace.so, copies everything off, then runs the diagnostic `unload` step (rmmod + panfrost
bind; in job 16 this reset the board: that is now expected-possible, the script waits for the board and restores).
Nothing is installed into the system; the blob stays in /root/armblob (never in an image or a commit).
Results: harness/research/arm-blob/traces/runner-j64/ (git-ignored; leave them there).
Submitted 2026-11-06 by the kbase-traces fix agent (status.md work list item 8): rerun of job 16 with the kbtrace
segfault fixed, bounded ssh everywhere, check-12 regex fixed, restore without rmmod.
