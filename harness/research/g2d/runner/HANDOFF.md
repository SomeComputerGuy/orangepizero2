# H616 G2D V4L2 m2m converter, runner job g2d: handoff

Command: `bash harness/research/g2d/runner/g2d-job.sh g2d`

Purpose: mechanical check of the kernel branch `fix/sunxi-h616-g2d` (armbian-build worktree `wt-g2d`, see
harness/research/g2d/RESULTS.md): the H616 G2D mixer as a V4L2 mem2mem colour converter and scaler (driver
`sun50i-g2d`, DT node `g2d@1480000`, IOMMU master 6, CCU reset `RST_BUS_G2D`). The board runs v4l2-compliance, a
matrix of conversions and scalings with the test client harness/research/g2d/tool/out/g2dconv (static aarch64, built by
tool/build.sh), and two GStreamer v4l2convert pipelines. The board generates the analytic input pattern (smooth
gradients + a sine) itself; the host generates the same pattern directly in each destination format and size as the
reference and compares the copied-back output channel by channel (tool/g2dcmp.py, numpy). All colour math is in the
tool, none in the runner.

Precondition (coordinator): merge `fix/sunxi-h616-g2d` into `test-cumulative`, build the next cumulative kernel and
serve it as kernel-check/vdec-serve/Image.<tag> + modules-<tag>.tgz (the kernel config gains
`CONFIG_VIDEO_SUN50I_G2D=m`). The script installs the NEWEST cumulative tag (last line of
kernel-check/cumulative-kernels.txt) via harness/research/vdec-perf/install-kernel.sh with the one-shot fallback armed;
the HTTP server on 10.56.0.1:8643 must be up (ship.sh). It checks that the branch head (FIX in the script) is an
ancestor of the tag's commit and that the booted kernel has the driver bound at
/sys/bus/platform/drivers/sun50i-g2d/1480000.g2d; otherwise it writes BLOCKED and exits 2 (report that, not a FAIL,
with files/g2d/probe-dmesg.txt if it exists). The client is shipped to /root/g2d/g2dconv when the board copy differs.
The board must start on the stock image kernel.

DEV or TEST: DEV-length, about 12 min: install + reboot (~3 min), compliance (~1 min), 49 conversion cases incl. a
2048x2048 and three 1080p ones (~3 min, the board generates the inputs), 2 gst runs (~1 min), copy-back of ~20 MB of
outputs (~1 min), restore (~1 min). Resumable: re-running skips chunks listed in logs/runner-g2d/state (one chunk).
The stock kernel vmlinuz-7.3.1-edge-sunxi64 is restored at the end and before every lock hand-over.

Fail fast: the serial log and the chunk's dmesg are watched for `Unable to handle|Oops|WARNING:|workqueue
lockup|iommu.*fault|Page fault|hung task`; a hit ends the job (exit 3, lines in logs/runner-g2d/OOPS): report FAIL
(OOPS) with the OOPS content and the last 10 lines of runner.log. An IOMMU fault here means the G2D read or wrote
outside its buffers: report it verbatim (it names the master and the address).

Results: harness/research/g2d/logs/runner-g2d/: runner.log, results.txt (one line per value: `g2d <run> <key>
<value>`), chunk-g2d.txt, ref/ (host references), files/g2d/{kernel.txt,probe.txt,probe-dmesg.txt,formats.txt,
compliance.txt,compliance-s.txt,<case>.txt,gst.txt,gst-inspect.txt,out/<case>.raw,dmesg-chunk.txt}, OOPS / BLOCKED only
when they happened.

Exit codes: 0 = chunk ran, judge with the checks below; 3 = Oops/WARN/IOMMU fault, FAIL; 2 = blocked (report BLOCKED
and the last 10 lines of runner.log); 1 = setup or lock error.

## Checks (mechanical, all on results.txt unless stated)
1. runner.log contains a `kernel: ` line and `kernel g2d: bound`. Report both.
2. Probe: `g2d probe driver_lines` >= 1, `g2d probe iommu_group 1`, `g2d probe device /dev/videoN` (not `none`) ->
   PASS, else FAIL (report files/g2d/probe-dmesg.txt). Also report `g2d probe clk_rate` (expected 300000000),
   `formats_out` and `formats_cap` (expected 18 each). If `device none`: every later check is FAIL (NO-DEVICE).
3. Compliance: `g2d compliance failed 0` and `g2d compliance rc 0` -> PASS, else FAIL: report `succeeded`, `failed`,
   `warnings` and every `g2d compliance FAILLINE` line. `g2d compliance-s failed` / `succeeded` / `warnings` (the
   streaming variant) are informational: report them and the FAILLINE lines, not pass/fail.
4. Conversions, for every case named in the first column of CASES in g2d-job.sh (49 cases, rgb-copy .. max-size):
   `g2d <case> rc 0` and `g2d <case> pass 1` -> PASS; else FAIL with `reason` (TIMEOUT, BUFERR, no_output), `max_dev`,
   `tol`, `over_tol`, the per-channel `*_max` values and `uvswap`. Report per case: `avg_us` (conversion time) and
   `max_dev`. `uvswap 1` on a failing YUV case means the output matches the reference with U and V swapped: report it
   as such (it is a plane-order bug, the next agent fixes a table entry). `alpha_min`/`alpha_max` (RGB outputs) are
   informational: report min and max once per case.
5. GStreamer: `g2d gst element 1` and `g2d gst device` equal to `g2d gst device_expected` -> PASS (v4l2convert exists
   and uses the G2D node), else FAIL (report files/g2d/gst-inspect.txt first 20 lines). `g2d gst-rgb2nv12 rc 0` +
   `pass 1`, `g2d gst-nv122rgb rc 0` + `pass 1` -> PASS, else FAIL with `max_dev`, `reason` and files/g2d/<case>.txt.
6. dmesg: `g2d all dmesg_bad 0`, `g2d all iommu_faults 0`, `g2d all g2d_timeouts 0` -> PASS; else FAIL, copy the
   matching lines from files/g2d/dmesg-chunk.txt exactly. Report `g2d all g2d_dmesg_lines` and the `DMESG:` lines of
   chunk-g2d.txt (first 20).

The summary must list: the kernel line, checks 1-3 and 5-6 with their values, the per-case table (case, rc, pass,
max_dev, avg_us, uvswap when 1) for check 4 with the count of PASS/FAIL cases, the state file content, and
OOPS/BLOCKED verbatim if they exist.
