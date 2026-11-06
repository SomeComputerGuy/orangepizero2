#!/bin/bash
# Stage a Mesa build (stripped) to the board under /root/opiz2-mesa/<name>. Never touches system dirs.
# Usage: deploy.sh <builddir> <name>
set -e
. /home/aruni/orangepizero2/mesa-work/tools/env.sh
[ -n "$MESA_ENV" ] && . "$MESA_ENV"
B=$1; N=$2; T=$MW/deploy/$N
rm -rf $T $MW/stage-$N; DESTDIR=$MW/stage-$N meson install -C $MW/$B --quiet >/dev/null
mkdir -p $T/lib; cp -a $MW/stage-$N/usr/lib/aarch64-linux-gnu/. $T/lib/
find $T/lib -type f -name '*.so*' -exec aarch64-linux-gnu-strip --strip-debug {} \;
sed "s|libEGL_mesa.so.0|/root/opiz2-mesa/$N/lib/libEGL_mesa.so.0|" $MW/stage-$N/usr/share/glvnd/egl_vendor.d/50_mesa.json > $T/50_mesa.json
cat > $T/env.sh <<EOT
export LD_LIBRARY_PATH=/root/opiz2-mesa/$N/lib
export __EGL_VENDOR_LIBRARY_FILENAMES=/root/opiz2-mesa/$N/50_mesa.json
export LIBGL_DRIVERS_PATH=/root/opiz2-mesa/$N/lib/dri
export GBM_BACKENDS_PATH=/root/opiz2-mesa/$N/lib/gbm
EOT
if [ -e $T/lib/libRusticlOpenCL.so.1 ]; then cat >> $T/env.sh <<EOT
export OCL_ICD_FILENAMES=/root/opiz2-mesa/$N/lib/libRusticlOpenCL.so.1
export RUSTICL_ENABLE=panfrost
EOT
fi
for j in $MW/stage-$N/usr/share/vulkan/icd.d/panfrost_icd*.json; do [ -e "$j" ] || continue
  sed "s|\"library_path\": *\"[^\"]*libvulkan_panfrost.so\"|\"library_path\": \"/root/opiz2-mesa/$N/lib/libvulkan_panfrost.so\"|" "$j" > $T/panfrost_icd.json
  echo "export VK_DRIVER_FILES=/root/opiz2-mesa/$N/panfrost_icd.json" >> $T/env.sh; done
H=/home/aruni/orangepizero2/harness
. $H/ssh-opts.sh; timeout 900 rsync -a --delete -e "/usr/bin/ssh ${BOARD_SSH_OPTS[*]}" $T/ root@10.56.0.107:/root/opiz2-mesa/$N/
du -sh $T
