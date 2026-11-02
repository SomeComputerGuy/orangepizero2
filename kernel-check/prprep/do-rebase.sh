#!/usr/bin/env bash
# Create pr/<name> = own commits cherry-picked onto parent, per rebase-specs.txt. Never touches existing branches.
W=/home/aruni/orangepizero2/wt-prprep-rebase; cd "$W" || exit 1
G="git -c core.hooksPath=/nonexistent"
while IFS='|' read -r name parent commits; do
	name=$(echo $name); parent=$(echo $parent); [[ -z $name || $name == \#* ]] && continue
	if git rev-parse -q --verify "refs/heads/pr/$name" > /dev/null; then echo "SKIP exists pr/$name"; continue; fi
	if ! git rev-parse -q --verify "$parent" > /dev/null; then echo "FAIL pr/$name: parent $parent missing"; continue; fi
	git checkout -q --detach "$parent"
	ok=1; note=""
	for c in $commits; do
		if ! $G cherry-pick --allow-empty --keep-redundant-commits "$c" > /tmp/prprep-cp.log 2>&1; then
			ok=0; note="conflict at $c: $(git diff --name-only --diff-filter=U | tr '\n' ' ')"; $G cherry-pick --abort; break
		fi
		if git diff --quiet HEAD^ HEAD; then note="$note empty:$c"; fi
	done
	if (( ok )); then git branch "pr/$name" HEAD; echo "OK pr/$name $(git rev-parse --short HEAD)$note"; else echo "CONFLICT pr/$name $note"; fi
done < /home/aruni/orangepizero2/kernel-check/prprep/rebase-specs.txt
git checkout -q --detach origin/main
