#!/bin/sh
# Board-side: dEQP-VK subset only (deqp-vk from vulkan-cts-1.4.6.2, see build-deqp-vk.sh). Resumable.
# Start: systemd-run --unit=cts-vk --collect -p MemoryMax=600M -p MemorySwapMax=64M -p OOMPolicy=continue sh /root/cts/run-vk-subset.sh [OUTNAME [CASELIST-NAME]]
# vk-main-1in100 = every 100th line of the 1.4.6.2 vk-main (awk NR%100==1), built by build-deqp-vk.sh
# Env = Mesa CI panfrost-g52-vk job (src/panfrost/ci/gitlab-ci.yml).
set -e
V=/root/cts/deqp-vk; R=/root/cts/results/${1:-vk-subset-1.4.6.2}; L=$V/mustpass/${2:-vk-subset}.txt
export VK_DRIVER_FILES=/usr/share/vulkan/icd.d/panfrost_icd.json VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/panfrost_icd.json
export PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1 MESA_VK_IGNORE_CONFORMANCE_WARNING=1 PANVK_DEBUG=sync
python3 $V/deqp-run.py --deqp $V/deqp-vk --caselist $L --out $R --jobs 1 --timeout 300
sync
