# Job 13-vp9-upsize (DEV, ~10 min, 2 chunks of <= 3 min, resumable)
Package: harness/vp9-vectors/HANDOFF-upsize.md (command `bash harness/vp9-vectors/run-upsize.sh`, checks 0-6 there).
Kernel: newest cumulative, which must contain armbian-build 7897dec08 (fix/sunxi-cedrus-vp9-inter-upsize, pushed to
fork, NOT yet merged into test-cumulative at submission): the script checks that with git first and exits 2 with
logs/upsize/BLOCKED if the newest cumulative kernel lacks it (report verbatim, no board access then; the coordinator
merges + cumul-builds and re-queues). Tests the VP9 inter-frame UPSIZE vector vp90-2-22-svc_1280x720_3 (REMOVE_BUFS
renegotiation) + the 26 downsize vectors + a 25-vector profile-0 regression subset. Results: harness/vp9-vectors/logs/upsize/.
Submitted 2026-11-05 by the vp9-upsize agent.
