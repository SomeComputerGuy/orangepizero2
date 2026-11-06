# Job 16-kbase-traces (TEST, ~10-15 min in one chunk, resumable)
Package: harness/research/kbase-trace/runner/HANDOFF.md (command `bash harness/research/kbase-trace/runner/kbase-traces.sh`,
then `bash harness/research/kbase-trace/runner/kbase-traces.sh --check` prints checks 1-11 as PASS/FAIL lines).
Kernel: the script installs the newest cumulative kernel itself (install-kernel.sh with the fallback armed, as
ocl-job.sh does; it must carry the BTF dedup fix bd60a159b, c7+; the board must start on the stock kernel) and restores
the stock image kernel at the end. It loads the out-of-tree Arm kbase (bifrost_kbase.ko, built against that kernel) with
panfrost unbound at runtime, runs the gles32probe GS/tess cases on the Arm libmali g24p0 blob plain and under kbtrace.so,
then rmmod + rebinds panfrost. Nothing is installed into the system; the blob stays in /root/armblob (never in an image
or a commit).
Results: harness/research/arm-blob/traces/runner/ (git-ignored; leave them there).
Submitted 2026-11-05 by the kbase-gles32 agent (docs/status.md item 8 step 1: GLES 3.2 reference traces; the c3 attempt
failed on module BTF validation, fixed by bd60a159b in c7+; this is the first run on a fixed kernel).
