#!/usr/bin/env bash
# Run Armbian's own kernel preparation code outside the framework (rootless), so the check build matches the
# real build:
#   armbian-prep.sh drivers <kernel-tree>  : the full driver harness (lib/functions/compilation/patch/
#                                            drivers-harness.sh + drivers_network.sh: xradio, rtl8189es/fs,
#                                            rtl8192eu, uwe5622, rtw88, wifi injection, bluetooth ...), with the
#                                            same driver list, KERNEL_DRIVERS_SKIP, conditions and patch/misc fixes.
#   armbian-prep.sh config <kernel-tree>   : every armbian_kernel_config__* hook of lib/functions/compilation/
#                                            armbian-kernel.sh (BTF, EXPERT, nftables, docker, ...) on .config,
#                                            before olddefconfig, as kernel_config_initialize() does.
# Env: ARMBIAN (armbian-build tree, default the main checkout), WORK (cache dir for driver git sources),
#      LINUXFAMILY=sunxi64 BRANCH=edge ARCH=arm64 KERNEL_MAJOR_MINOR=7.3, KERNEL_DRIVERS_SKIP (space-separated).
# Driver sources are fetched into $WORK/dl/driver-sources (never into the armbian-build cache, which the user's
# build owns).
set -eo pipefail # no -u: the Armbian code reads unset variables (KERNEL_BTF, ...)
cmd="${1:?usage: armbian-prep.sh drivers|config <kernel-tree>}"
tree="$(cd "${2:?kernel tree}" && pwd)"
ARMBIAN="${ARMBIAN:-/home/aruni/orangepizero2/armbian-build}"
WORK="${WORK:-/home/aruni/orangepizero2/kernel-check/work}"
declare -g LINUXFAMILY="${LINUXFAMILY:-sunxi64}" BRANCH="${BRANCH:-edge}" ARCH="${ARCH:-arm64}"
declare -g KERNEL_MAJOR_MINOR="${KERNEL_MAJOR_MINOR:-7.3}" GITHUB_SOURCE="${GITHUB_SOURCE:-https://github.com}"
read -r -a KERNEL_DRIVERS_SKIP <<< "${KERNEL_DRIVERS_SKIP:-}" || true

# --- minimal stand-ins for the framework helpers the Armbian code calls ---
display_alert() { [[ "${3:-}" == debug || "${3:-}" == git ]] || echo "  [armbian] $1${2:+ [ $2 ]}"; }
exit_with_error() { echo "armbian-prep: ERROR: $*" >&2; exit 1; }
run_host_command_logged() { "$@" > /dev/null; }
process_patch_file() { # same steps as lib/functions/compilation/patch/patching.sh
	local patch="$1" status="$2"
	{ lsdiff -s --strip=1 "${patch}" | grep '^+' || true; } | awk '{print $2}' | xargs -r -I % sh -c 'rm -f %'
	patch --batch -p1 -N --input="${patch}" --quiet --reject-file=- ||
		exit_with_error "patch failed: $status ${patch##"${SRC}"/}"
	display_alert "* $status ${patch##"${SRC}"/}" ""
}
fetch_from_repo() { # url dir ref ref_subdir: Armbian layout ${SRC}/cache/sources/<dir>[/<ref>]
	local url="$1" dir="$2" ref="$3" sub="${4:-no}" name="${3#*:}" target
	target="${SRC}/cache/sources/${dir}"; [[ $sub == yes ]] && target+="/${name}"
	mkdir -p "$target"
	(
		cd "$target"
		[[ -d .git ]] || git init -q .
		if ! git -c advice.detachedHead=false checkout -f -q "$name" 2> /dev/null; then
			git fetch -q --depth 1 --no-tags "$url" "$name"
			git -c advice.detachedHead=false checkout -f -q FETCH_HEAD
		fi
		git clean -q -d -f
	)
}

# Shadow SRC: Armbian's patch/ and lib/ (read-only use), private cache/sources.
SRC="$WORK/dl/armbian-src"
mkdir -p "$SRC/cache" "$WORK/dl/driver-sources"
ln -sfn "$ARMBIAN/patch" "$SRC/patch"
ln -sfn "$ARMBIAN/lib" "$SRC/lib"
ln -sfn "$WORK/dl/driver-sources" "$SRC/cache/sources"
export SRC

case "$cmd" in
drivers)
	# shellcheck source=/dev/null
	source "$ARMBIAN/lib/functions/compilation/patch/drivers_network.sh"
	# The driver list is the one in kernel_drivers_prepare_harness() (parsed, so it never drifts).
	mapfile -t all_drivers < <(sed -n '/^function kernel_drivers_prepare_harness/,/^}/p' \
		"$ARMBIAN/lib/functions/compilation/patch/drivers-harness.sh" |
		sed -n '/declare -a all_drivers=(/,/)/p' | grep -oE '^\s*driver_[A-Za-z0-9_]+' | tr -d '[:space:]\n' | sed 's/driver_/\ndriver_/g' | sed '/^$/d')
	[[ ${#all_drivers[@]} -gt 5 ]] || exit_with_error "could not parse the driver list"
	n=0
	for driver in "${all_drivers[@]}"; do
		for skip in "${KERNEL_DRIVERS_SKIP[@]}"; do [[ $driver == "$skip" ]] && continue 2; done
		version="${KERNEL_MAJOR_MINOR}" kernel_work_dir="$tree" kerneldir="$tree"
		cd "$tree"
		"$driver"
		n=$((n + 1))
	done
	cd "$tree"
	echo "driver harness: $n drivers run (${#all_drivers[@]} in Armbian's list)"
	;;
config)
	cd "$tree"
	[[ -f .config ]] || exit_with_error "no .config in $tree"
	sed -i -e '$a\' .config
	# shellcheck source=/dev/null
	source "$ARMBIAN/lib/functions/compilation/armbian-kernel.sh"
	declare -A opts_val=()
	declare -a opts_y=() opts_n=() opts_m=() kernel_config_modifying_hashes=()
	# Same order as call_extension_method (general-numeric, ignore-case sort of the hook function names).
	mapfile -t hooks < <(compgen -A function | grep '^armbian_kernel_config__' | sort --general-numeric-sort --ignore-case)
	for h in "${hooks[@]}"; do "$h"; done
	armbian_kernel_config_apply_opts_from_arrays
	echo "armbian_kernel_config: ${#hooks[@]} hooks, ${#kernel_config_modifying_hashes[@]} options"
	;;
*) exit_with_error "unknown command $cmd" ;;
esac
