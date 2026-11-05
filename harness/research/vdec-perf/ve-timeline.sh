#!/bin/bash
# Usage: ve-timeline.sh <command...>
# Per-job timeline of the cedrus VE for any decoder client (ftrace function events, mono clock):
#   setup  = cedrus_device_run -> *_trigger      (CPU: controls, register/table writes)
#   ve     = *_trigger -> cedrus_irq             (VE busy)
#   wq     = cedrus_irq -> v4l2_m2m_device_run_work (m2m next-job worker latency, only when a job was ready)
#   gap    = cedrus_irq -> next cedrus_device_run, split by whether the next request was already queued at IRQ
#            time ("ready": kernel latency) or not ("starved": the client had not queued it yet).
# The last line gives the share of wall time the VE was idle for each reason.
T=/sys/kernel/tracing
echo 0 > $T/tracing_on; echo > $T/trace; echo mono > $T/trace_clock; echo 16384 > $T/buffer_size_kb
echo function > $T/current_tracer
: > $T/set_ftrace_filter
for f in cedrus_device_run cedrus_irq cedrus_vp9_trigger cedrus_h265_trigger cedrus_avs2_trigger cedrus_h264_trigger \
         v4l2_m2m_request_queue v4l2_m2m_device_run_work; do echo $f >> $T/set_ftrace_filter 2>/dev/null; done
echo 1 > $T/tracing_on
s=$(date +%s.%N); "$@" > /tmp/vtl.out 2>&1; rc=$?; e=$(date +%s.%N)
echo 0 > $T/tracing_on
cp $T/trace /tmp/vtl.trace
awk -v wall=$(echo "$e - $s" | bc) -v rc=$rc '
function ts() { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+\.[0-9]+:$/) return $i + 0; return -1 }
/^#/ { next }
{ t = ts(); if (t < 0) next }
/ v4l2_m2m_request_queue/ { pend++; next }
/ v4l2_m2m_device_run_work/ { if (irq && !wqd) { wq += t - irq; nwq++; wqd = 1 } next }
/ cedrus_device_run/ {
	if (pend > 0) pend--
	if (irq) { g = t - irq; if (readyat) { gr += g; nr++ } else { gs += g; ns++; if (g > mxs) mxs = g } }
	run = t; trig = 0; irq = 0; if (!first) first = t; next }
/_trigger/ { if (run) { trig = t; setup += t - run; nset++ } next }
/ cedrus_irq/ { if (trig) { ve += t - trig; nve++; if (t - trig > mxve) mxve = t - trig }
	irq = t; last = t; readyat = (pend > 0); wqd = 0; trig = 0; run = 0; next }
END {
	span = last - first; if (nve == 0) { print "no jobs, rc=" rc; exit }
	printf "rc=%d jobs=%d wall=%.2fs span=%.2fs | setup %.2fms ve %.2fms (max %.2f) | gap ready n=%d avg %.3fms (wq %.3fms) | gap starved n=%d avg %.2fms max %.2fms\n", \
		rc, nve, wall, span, setup/nset*1000, ve/nve*1000, mxve*1000, nr, nr ? gr/nr*1000 : 0, nwq ? wq/nwq*1000 : 0, ns, ns ? gs/ns*1000 : 0, mxs*1000
	printf "fps: ve-only %.1f, ve+setup %.1f, pipeline(span) %.1f, wall %.1f | idle share: setup %.1f%% ready-gap %.1f%% starved %.1f%%\n", \
		nve/ve, nve/(ve+setup), nve/span, nve/wall, setup/span*100, gr/span*100, gs/span*100
}' /tmp/vtl.trace
echo nop > $T/current_tracer; : > $T/set_ftrace_filter; echo local > $T/trace_clock
