#!/usr/bin/env bash
# Build + install bleeding-edge FFmpeg (git master) on the host into /usr/local as static binaries.
# System libav* (used by other apps) are untouched. Rerun to update. Undo: sudo rm /usr/local/bin/{ffmpeg,ffprobe}
set -euo pipefail
SRC=~/src/ffmpeg
sudo apt-get install -y nasm git libx264-dev libx265-dev libvpx-dev libdav1d-dev libaom-dev \
	libopus-dev libvorbis-dev libmp3lame-dev libdrm-dev libva-dev libxml2-dev
if [[ -d $SRC/.git ]]; then git -C "$SRC" pull --ff-only; else git clone https://git.ffmpeg.org/ffmpeg.git "$SRC"; fi
cd "$SRC"
./configure --prefix=/usr/local --cc="ccache gcc" --enable-gpl --enable-version3 \
	--disable-shared --enable-static --disable-doc \
	--enable-libx264 --enable-libx265 --enable-libvpx --enable-libdav1d --enable-libaom \
	--enable-libopus --enable-libvorbis --enable-libmp3lame --enable-libdrm --enable-vaapi --enable-libxml2
make -j"$(nproc)"
sudo make install
hash -r
echo "== installed: $(command -v ffmpeg)  commit $(git log -1 --format='%H %cd')"
/usr/local/bin/ffmpeg -hide_banner -decoders | grep -i cavs
