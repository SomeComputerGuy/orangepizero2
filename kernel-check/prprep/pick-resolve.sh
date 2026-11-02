#!/usr/bin/env bash
# pick-resolve.sh <new branch> <parent> <commits...>: cherry-pick, resolving series.conf conflicts with series-merge.py
set -u
name=$1; parent=$2; shift 2
W=/home/aruni/orangepizero2/wt-prprep-rebase; A=/home/aruni/orangepizero2/armbian-build; S=patch/kernel/archive/sunxi-7.3/series.conf
G="git -c core.hooksPath=/nonexistent"
cd "$W"; git rev-parse -q --verify "refs/heads/$name" >/dev/null && { echo "exists $name"; exit 1; }
git checkout -q --detach "$parent"
for c in "$@"; do
	if ! $G cherry-pick "$c" > /dev/null 2>&1; then
		u=$(git diff --name-only --diff-filter=U)
		if [[ $u != "$S" ]]; then echo "UNRESOLVABLE $c: $u"; $G cherry-pick --abort; exit 2; fi
		git checkout -q HEAD -- "$S" 2>/dev/null || git show HEAD:"$S" > "$S"
		python3 -I /home/aruni/orangepizero2/kernel-check/prprep/series-merge.py "$A" "$c" "$S" stonking-orangepizero2
		git add "$S"; $G -c core.editor=true cherry-pick --continue > /dev/null 2>&1 || { echo "continue failed $c"; exit 3; }
		echo "  resolved series.conf for $c"
	fi
done
git branch "$name" HEAD; echo "OK $name $(git rev-parse --short HEAD)"
git checkout -q --detach origin/main
