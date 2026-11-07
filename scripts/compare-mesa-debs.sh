#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Compare our mesa rebuild (out/debs-media, cross-built) with the archive's arm64 mesa debs of the same Ubuntu version.
# Usage: compare-mesa-debs.sh <archive-deb-dir> <our-deb-dir> <ubuntu-buildlog(.gz)> <our-buildlog> <out-dir>
# Writes <out-dir>/{1-control,2-files,3-symbols,4-config,5-elf}.diff/.txt and prints one RESULT line per check.
# Our version string differs by "+opiz2.N": it is normalised away before diffing.
set -u
A=$1 O=$2 UL=$3 OL=$4 R=$5; mkdir -p "$R"; T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
NM=aarch64-linux-gnu-nm
norm() { sed -E 's/\+opiz2\.[0-9]+//g'; }
ours() { ls "$O"/*_*+opiz2*_arm64.deb | while read -r d; do s=$(dpkg-deb -f "$d" Source); [ "${s%% *}" = mesa ] && echo "$d"; done; }
mapfile -t OD < <(ours); mapfile -t AD < <(ls "$A"/*.deb)
pk() { dpkg-deb -f "$1" Package; }
# 1 control: package set, version, relationship fields
for d in "${AD[@]}"; do p=$(pk "$d"); dpkg-deb -f "$d" Package Version Architecture Multi-Arch Depends Pre-Depends Recommends Suggests Provides Breaks Conflicts Replaces Enhances > "$T/a.$p"; done
for d in "${OD[@]}"; do p=$(pk "$d"); dpkg-deb -f "$d" Package Version Architecture Multi-Arch Depends Pre-Depends Recommends Suggests Provides Breaks Conflicts Replaces Enhances | norm > "$T/o.$p"; done
(cd "$T" && ls a.* | sed 's/^a\.//' | sort) > "$R/1-packages-archive.txt"; (cd "$T" && ls o.* | sed 's/^o\.//' | sort) > "$R/1-packages-ours.txt"
{ diff "$R/1-packages-archive.txt" "$R/1-packages-ours.txt"; for p in $(cat "$R/1-packages-archive.txt"); do [ -f "$T/o.$p" ] && diff -u --label "archive $p" --label "ours $p" "$T/a.$p" "$T/o.$p"; done; } > "$R/1-control.diff"
echo "RESULT 1 control: $(cat "$R/1-packages-archive.txt" | wc -l) archive / $(cat "$R/1-packages-ours.txt" | wc -l) ours packages, diff lines $(grep -c '^[-+<>][^-+]' "$R/1-control.diff")"
# 2 file lists (names, symlink targets, modes)
for d in "${AD[@]}"; do dpkg-deb -c "$d" | awk '{m=$1; $1=$2=$3=$4=$5=""; sub(/^ +/,""); print m, $0}' | norm | sort > "$T/fa.$(pk "$d")"; done
for d in "${OD[@]}"; do dpkg-deb -c "$d" | awk '{m=$1; $1=$2=$3=$4=$5=""; sub(/^ +/,""); print m, $0}' | norm | sort > "$T/fo.$(pk "$d")"; done
: > "$R/2-files.diff"; for p in $(cat "$R/1-packages-archive.txt"); do [ -f "$T/fo.$p" ] && diff -u --label "archive $p" --label "ours $p" "$T/fa.$p" "$T/fo.$p" >> "$R/2-files.diff"; done
echo "RESULT 2 file lists: diff lines $(grep -c '^[-+][^-+]' "$R/2-files.diff")"
# 3 exported dynamic symbols of every shared object
mkdir -p "$T/xa" "$T/xo"; for d in "${AD[@]}"; do dpkg-deb -x "$d" "$T/xa"; done; for d in "${OD[@]}"; do dpkg-deb -x "$d" "$T/xo"; done
: > "$R/3-symbols.diff"; n=0
while read -r f; do n=$((n+1))
  [ -f "$T/xo/$f" ] || { echo "MISSING in ours: $f" >> "$R/3-symbols.diff"; continue; }
  diff -u --label "archive $f" --label "ours $f" <($NM -D --defined-only "$T/xa/$f" 2>&1 | awk '{print $NF, $(NF-1)}' | sort) <($NM -D --defined-only "$T/xo/$f" 2>&1 | awk '{print $NF, $(NF-1)}' | sort) >> "$R/3-symbols.diff"
done < <(cd "$T/xa" && find . -type f -name '*.so*' | sort)
echo "RESULT 3 dynamic symbols: $n shared objects compared, diff lines $(grep -c '^[-+][^-+]\|^MISSING' "$R/3-symbols.diff")"
# 4 configuration: meson setup options and the configure summary
cfg() { { zcat -f "$1" | grep -m1 -oE 'meson setup .*' | tr ' ' '\n' | grep '^-D' | sort; echo "--- summary"; zcat -f "$1" | awk '/^mesa 26/{p=1} p&&/User defined options/{exit} p' | sed -E 's/ +$//'; } ; }
cfg "$UL" > "$R/4-config-ubuntu.txt"; cfg "$OL" | sed -E 's/aarch64-linux-gnu-//g' > "$R/4-config-ours.txt"
diff -u "$R/4-config-ubuntu.txt" "$R/4-config-ours.txt" > "$R/4-config.diff"
echo "RESULT 4 config: $(grep -c '^-D' "$R/4-config-ubuntu.txt") meson options, diff lines $(grep -c '^[-+][^-+]' "$R/4-config.diff")"
# 5 every ELF in our debs is aarch64
(cd "$T/xo" && find . -type f -exec file -N {} + | grep ': *ELF') > "$R/5-elf.txt"
echo "RESULT 5 ELF: $(wc -l < "$R/5-elf.txt") ELF files, not aarch64: $(grep -vc 'ARM aarch64' "$R/5-elf.txt")"
