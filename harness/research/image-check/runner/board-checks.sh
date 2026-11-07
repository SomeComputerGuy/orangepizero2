#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Board side of runner job 69-image-check. Run by image-check.sh as `bash -l board-checks.sh <step> <kv>` (a login
# shell over ssh: pam_env + /etc/profile, like a user login). Prints KEY lines that image-check.sh --check judges.
# Steps: pkgs gst libav venv vulkan gles ocl dmesg. Never changes the system (results only under /root/imgchk).
step=$1 KV=${2:-}
D=/root/imgchk; mkdir -p $D; cd $D || exit 1
CTS=/root/cts; VK=$CTS/deqp-vk; GL=$CTS/deqp-gles; CL=$CTS/opencl-cts
irq() { awk '/1c0e000.video-codec/{s+=$2+$3+$4+$5} END{print s+0}' /proc/interrupts; }
case $step in
pkgs)
  echo "UNAME $(uname -r) | $(uname -v)"
  echo "IMAGE-LINK $(readlink /boot/Image)"
  echo "SYSTEM-STATE $(systemctl is-system-running 2>&1)"
  for p in gstreamer1.0-plugins-bad gstreamer1.0-plugins-good libgl1-mesa-dri libegl-mesa0 mesa-libgallium mesa-vulkan-drivers mesa-opencl-icd libgbm1; do
    echo "PKG $p $(dpkg-query -W -f '${db:Status-Abbrev}${Version}' $p 2>/dev/null || echo not-installed)"; done
  # every installed package built from these three sources must be our +opiz2 build
  n=$(dpkg-query -W -f '${db:Status-Abbrev} ${source:Package} ${Package} ${Version}\n' | awk '$1 == "ii" && $2 ~ /^(mesa|gst-plugins-bad1\.0|gst-plugins-good1\.0)$/' | tee $D/ours.txt | grep -vc '+opiz2')
  echo "NOT-OURS $n $(awk '$4 !~ /\+opiz2/ {print $3"="$4}' $D/ours.txt | tr '\n' ' ')"
  echo "OURS-COUNT $(wc -l < $D/ours.txt)"
  echo "REPO $(cat /etc/apt/sources.list.d/opiz2-media.list 2>/dev/null) | debs $(ls /opt/opiz2-media/*.deb 2>/dev/null | wc -l)"
  echo "PIN $(apt-cache policy libgl1-mesa-dri 2>/dev/null | grep -m1 -E '^ \*\*\* ' -A1 | tail -1 | tr -s ' ')"
  echo "FFMPEG $(dpkg-query -W -f '${db:Status-Abbrev}${Version}' ffmpeg 2>/dev/null || echo not-installed)"
  ;;
gst)
  for e in v4l2sljpegdec v4l2jpegdec v4l2slh264dec v4l2slh265dec v4l2slmpeg2dec v4l2slvp8dec v4l2slvp9dec jpegdec avdec_mpeg2video; do
    gst-inspect-1.0 --exists $e && echo "ELEM $e yes" || echo "ELEM $e no"; done
  echo "V4L2CODECS $(gst-inspect-1.0 v4l2codecs 2>/dev/null | grep -oE '^ *v4l2sl[a-z0-9]+' | tr -d ' ' | sort -u | tr '\n' ' ')"
  echo "RANK-ENV ${GST_PLUGIN_FEATURE_RANK:-unset}"
  echo "RANK-V4L2JPEGDEC $(gst-inspect-1.0 v4l2jpegdec 2>/dev/null | grep -m1 -i 'rank' | tr -s ' ')"
  # one 4:2:0 baseline picture, decoded by each JPEG decoder explicitly and by decodebin
  rm -f p.jpg; gst-launch-1.0 -q videotestsrc num-buffers=1 ! video/x-raw,width=320,height=240,format=I420 ! jpegenc ! filesink location=p.jpg >/dev/null 2>&1
  for e in v4l2sljpegdec v4l2jpegdec jpegdec; do
    i0=$(irq); timeout 60 gst-launch-1.0 -q filesrc location=p.jpg ! jpegparse ! $e ! videoconvert ! video/x-raw,format=I420 ! filesink location=o-$e.yuv > o-$e.log 2>&1; rc=$?; i1=$(irq)
    echo "JPEG $e rc=$rc size=$(stat -c %s o-$e.yuv 2>/dev/null || echo 0) irqs=$((i1-i0))"; done
  timeout 60 gst-launch-1.0 -v filesrc location=p.jpg ! jpegparse ! decodebin ! fakesink > db.log 2>&1; rc=$?
  echo "JPEG-AUTOPLUG rc=$rc picked=[$(grep -oE '(v4l2sl|v4l2)?jpegdec[0-9]+' db.log | sort -u | tr '\n' ' ')]"
  ;;
libav)  # job 24 check 1: MPEG-1 without MG1S on the image kernel -> decodebin takes gst-libav's software decoder
  v=$(grep -l cedrus /sys/class/video4linux/*/name 2>/dev/null | head -1); v=/dev/$(basename $(dirname $v))
  echo "MG1S $(v4l2-ctl -d $v --list-formats-out 2>/dev/null | grep -c MG1S) ($v)"
  echo "SWDEC $(for e in avdec_mpeg2video avdec_mpeg1video mpeg2dec; do gst-inspect-1.0 --exists $e && printf '%s ' $e; done)"
  echo "LIBAV-PKG $(dpkg-query -W -f '${db:Status-Abbrev}${Version}' gstreamer1.0-libav 2>/dev/null || echo not-installed)"
  i0=$(irq); timeout 120 gst-launch-1.0 -v filesrc location=$D/ccm1 ! decodebin ! videoconvert ! video/x-raw,format=I420 ! filesink location=ccm1.yuv > ccm1.log 2>&1; rc=$?; i1=$(irq)
  echo "CCM1-DB rc=$rc $(md5sum < ccm1.yuv 2>/dev/null | cut -c1-32) size=$(stat -c %s ccm1.yuv 2>/dev/null || echo 0) irqs=$((i1-i0)) picked=[$(grep -oE ':(v4l2slmpeg2dec|v4l2mpeg2dec|mpeg2dec|avdec_mpeg[a-z0-9]*)[0-9]*' ccm1.log | tr -d ':' | sort -u | tr '\n' ' ')]"
  ;;
venv)  # PAN_I_WANT_A_BROKEN_VULKAN_DRIVER everywhere: this login shell, the system manager, the user-manager generator
  echo "LOGIN-ENV ${PAN_I_WANT_A_BROKEN_VULKAN_DRIVER:-unset}"
  echo "ETC-ENVIRONMENT $(grep -c '^PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1$' /etc/environment)"
  echo "SYSTEMD-SYSTEM $(systemctl show-environment | grep -c '^PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1$')"
  echo "SYSTEMD-USER-CONF $(grep -c 'PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1' /etc/systemd/user.conf.d/60-opiz2-panvk.conf 2>/dev/null || echo 0)"
  g=/usr/lib/systemd/user-environment-generators/30-systemd-environment-d-generator
  echo "ENVIRONMENT-D $([ -x $g ] && $g 2>/dev/null | grep -c '^PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1$' || echo no-generator)"
  echo "SERVICE-ENV $(systemd-run --wait --pipe --collect -q sh -c 'echo ${PAN_I_WANT_A_BROKEN_VULKAN_DRIVER:-unset}' 2>&1 | tail -1)"
  ;;
vulkan)
  vulkaninfo --summary > vkinfo.txt 2>&1; echo "VULKANINFO rc=$?"
  # the block of the panvk device (from its GPU<n>: line to the next one)
  awk 'BEGIN{RS="GPU[0-9]+:"} /driverName *= *panvk/{print}' vkinfo.txt > vkpanvk.txt
  echo "PANVK-API $(grep -m1 -oE 'apiVersion *= *[0-9.]+' vkpanvk.txt | grep -oE '[0-9.]+$')"
  echo "PANVK-DEVICE $(grep -m1 -E 'deviceName' vkpanvk.txt | sed 's/.*= *//')"
  echo "PANVK-DRIVERINFO $(grep -m1 -E 'driverInfo' vkpanvk.txt | sed 's/.*= *//')"
  echo "NO-ENV-PANVK $(env -u PAN_I_WANT_A_BROKEN_VULKAN_DRIVER vulkaninfo --summary 2>/dev/null | grep -c 'driverName *= *panvk')"
  h=$(cat /sys/class/drm/card*-HDMI-A-*/status 2>/dev/null | grep -c '^connected')
  if [ "$h" -gt 0 ]; then timeout 60 vkcube --c 100 --wsi display > vkcube.txt 2>&1; echo "VKCUBE rc=$? hdmi=connected"
  else echo "VKCUBE not-run hdmi=disconnected (vkcube has no headless WSI; offscreen rendering = SMOKE below)"; fi
  n=$(dmesg | wc -l)
  cd $VK && VK_DRIVER_FILES=/usr/share/vulkan/icd.d/panfrost_icd.json timeout 300 ./deqp-vk --deqp-case='dEQP-VK.api.smoke.*' --deqp-log-images=disable --deqp-log-filename=$D/smoke.qpa > $D/smoke.txt 2>&1; echo "SMOKE rc=$?"
  echo "SMOKE-FAILED $(grep -E '^ *Failed:' $D/smoke.txt | tr -s ' ')"
  echo "SMOKE-TRIANGLE $(grep -A1 "dEQP-VK.api.smoke.triangle'" $D/smoke.txt | tail -1 | tr -s ' ')"
  # job 52's subgroup cases (need the 1.1 feature set: MESA_VK_VERSION_OVERRIDE=1.1 for this test only)
  for c in dEQP-VK.subgroups.basic.compute.subgroupelect dEQP-VK.subgroups.basic.graphics.subgroupelect dEQP-VK.subgroups.ballot_broadcast.compute.subgroupbroadcast_uint dEQP-VK.subgroups.basic.compute.subgroupbarrier dEQP-VK.subgroups.basic.compute.subgroupmemorybarrier dEQP-VK.subgroups.basic.compute.subgroupmemorybarriershared dEQP-VK.subgroups.basic.graphics.subgroupbarrier dEQP-VK.subgroups.clustered.graphics.subgroupclusteredmul_ivec4 dEQP-VK.subgroups.builtin_var.compute.subgroupsize_compute; do
    VK_DRIVER_FILES=/usr/share/vulkan/icd.d/panfrost_icd.json MESA_VK_VERSION_OVERRIDE=1.1 timeout 200 ./deqp-vk --deqp-case=$c --deqp-log-images=disable --deqp-log-shader-sources=disable --deqp-log-filename=$D/sg.qpa > $D/sg.txt 2>&1; rc=$?
    echo "SG $c rc=$rc result=[$(grep -E '^  (Pass|Fail|NotSupported|QualityWarning|Crash|Timeout|InternalError)' $D/sg.txt | head -1 | tr -s ' ')]"; done
  cd $D; echo "VK-DMESG $(dmesg | tail -n +$((n+1)) | grep -cE 'js fault|INSTR_INVALID_ENC|Page fault|Unhandled|gpu sched timeout')"
  ;;
gles)
  EGL_PLATFORM=surfaceless eglinfo -B -p surfaceless > eglinfo.txt 2>&1 || EGL_PLATFORM=surfaceless eglinfo > eglinfo.txt 2>&1
  echo "EGL-RENDERER $(grep -m1 -iE 'OpenGL ES profile renderer' eglinfo.txt | sed 's/.*: *//')"
  echo "EGL-VERSION $(grep -m1 -iE 'OpenGL ES profile version' eglinfo.txt | sed 's/.*: *//')"
  h=$(cat /sys/class/drm/card*-HDMI-A-*/status 2>/dev/null | grep -c '^connected')
  if [ "$h" -gt 0 ]; then timeout 60 kmscube -c 300 > kmscube.txt 2>&1; echo "KMSCUBE rc=$? hdmi=connected"; else echo "KMSCUBE not-run hdmi=disconnected"; fi
  n=$(dmesg | wc -l)
  export LD_LIBRARY_PATH=/root/cts/lib EGL_PLATFORM=surfaceless
  grep 'functional.shaders.derivate' $GL/mustpass/gles3-main.txt > $D/gles3-derivate.txt
  rm -rf $D/gles3-derivate; timeout 850 python3 $GL/deqp-run.py --deqp $GL/gles3/deqp-gles3 --caselist $D/gles3-derivate.txt --out $D/gles3-derivate --jobs 1 --timeout 180 > $D/gles-run.txt 2>&1; echo "GLES-RUN rc=$?"
  echo "GLES-SUMMARY $(tr '\n' ' ' < $D/gles3-derivate/summary.txt 2>/dev/null | tr -s ' ')"
  echo "GLES-DMESG $(dmesg | tail -n +$((n+1)) | grep -cE 'js fault|INSTR_INVALID_ENC|Page fault|Unhandled|gpu sched timeout')"
  ;;
ocl)
  clinfo > clinfo.txt 2>&1; echo "CLINFO rc=$? env RUSTICL_ENABLE=${RUSTICL_ENABLE:-unset}"
  echo "CL-PLATFORM $(grep -m1 -E '^ *Platform Name' clinfo.txt | sed 's/.*Name *//')"
  echo "CL-DEVICE $(grep -m1 -E '^ *Device Name' clinfo.txt | sed 's/.*Name *//')"
  echo "CL-VERSION $(grep -m1 -E '^ *Device Version' clinfo.txt | sed 's/.*Version *//')"
  n=$(dmesg | wc -l)
  rm -rf $D/ocl; timeout 1500 python3 $CL/clcts-run.py --cts $CL/test_conformance --profile $CL/opencl_conformance_tests_mesa.csv --out $D/ocl --timeout 800 --only '^(Atomics|C11 Atomics|Half Ops|Relationals|Compute Info|Workgroups|Subgroups|Select)$' > $D/ocl-run.txt 2>&1; echo "OCL-RUN rc=$?"
  awk -F, 'NR>1 {print "OCL-SUITE " $1 " " $2}' $D/ocl/binaries.csv 2>/dev/null
  echo "OCL-DMESG $(dmesg | tail -n +$((n+1)) | grep -cE 'js fault|INSTR_INVALID_ENC|Page fault|Unhandled|gpu sched timeout')"
  ;;
dmesg)
  dmesg > $D/dmesg.txt
  echo "DMESG-BAD $(grep -cE 'Oops|BUG:|Kernel panic|INSTR_INVALID_ENC|js fault|Unhandled fault' $D/dmesg.txt)"
  grep -E 'Oops|BUG:|Kernel panic|INSTR_INVALID_ENC|js fault|Unhandled fault' $D/dmesg.txt | head -10 | sed 's/^/DMESG-LINE /'
  ;;
*) echo "unknown step $step"; exit 1 ;;
esac
echo "STEP-DONE $step"
