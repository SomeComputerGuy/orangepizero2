#!/bin/bash
# static board FFmpeg from the shared set's final tree (OPi5 ffmpeg-shared/src 908ab79544 = patches/ffmpeg 0001-0312); output kernel-check/ffmpeg-deb/build-mg1s/ffmpeg
set -u
H=/home/aruni/orangepizero2; D=$H/kernel-check/ffmpeg-deb
[ -d $D/src-mg1s/.git ] || git clone -q --no-hardlinks /home/aruni/orangepi5/work/_out/ffmpeg-shared/src $D/src-mg1s || exit 1
git -C $D/src-mg1s checkout -q --detach 908ab7954468f01af7e31b849521328bcd06284a || exit 1
git -C $D/src-mg1s log --oneline -1
# the exported patches must be the ones in patches/ffmpeg (patch-id compare of the 35 code patches)
cd $D/src-mg1s && n=$(git rev-list --count n8.1.2..HEAD 2>/dev/null || git rev-list --count 908ab79544~35..HEAD); echo "commits on top of the base: $n"
bash $H/harness/ffmpeg/dev-build.sh $D/src-mg1s $D/build-mg1s 2>&1 | tail -5
$D/build-mg1s/ffmpeg -hide_banner -hwaccels 2>&1 | tr '\n' ' '; echo
file $D/build-mg1s/ffmpeg | cut -c1-120; sha256sum $D/build-mg1s/ffmpeg
echo FFBUILD-DONE
