#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Teach armbian-config's desktop YAML definitions a release they do not list yet.

Usage: configng-add-release.py <yaml_dir> <new_release> <base_release> [--no-armbian-repo]

Every mapping in every <yaml_dir>/*.yaml that has <base_release> as a key and no <new_release> key gets
<new_release> as a deep copy of the <base_release> entry: the per-DE `releases:` blocks (availability,
architectures, extra/removed packages), common.yaml's `releases:`, `browser:` map and `tier_overrides`.
This is the change a configng PR adding the release would make (docs/upstream-queue.md).

--no-armbian-repo: the image has no apt.armbian.com suite for the release (SKIP_ARMBIAN_REPO=yes), so
drop the packages that only exist there (chromium, code, armbian-imager) and the snap-transitional
Ubuntu .debs that cannot install in a build chroot (firefox, thunderbird, chromium-browser), and use
epiphany-browser (a real .deb in the Ubuntu archive) for the `browser` token.

Idempotent. Rewrites only the files it changes (comments are lost in those files; they are data files).
"""
import copy
import os
import sys

import yaml

ARMBIAN_ONLY = ["armbian-imager", "code", "chromium"]
SNAP_SHIMS = ["firefox", "thunderbird", "chromium-browser"]
LOCAL_BROWSER = "epiphany-browser"


def add_release(node, new, base):
    changed = False
    if isinstance(node, dict):
        if base in node and new not in node:
            node[new] = copy.deepcopy(node[base])
            changed = True
        for v in list(node.values()):
            changed |= add_release(v, new, base)
    elif isinstance(node, list):
        for v in node:
            changed |= add_release(v, new, base)
    return changed


def no_armbian_repo(name, data, new):
    if name != "common.yaml":
        return False
    browser = data.setdefault("browser", {})
    rel = browser.get(new)
    if not isinstance(rel, dict):
        rel = browser[new] = {}
    changed = False
    for arch in ("arm64", "armhf", "amd64", "riscv64"):
        if rel.get(arch) != LOCAL_BROWSER:
            rel[arch] = LOCAL_BROWSER
            changed = True
    releases = data.setdefault("releases", {})
    block = releases.get(new)
    if not isinstance(block, dict):
        block = releases[new] = {}
    removes = block.setdefault("packages_remove", [])
    for p in ARMBIAN_ONLY + SNAP_SHIMS:
        if p not in removes:
            removes.append(p)
            changed = True
    return changed


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 3:
        sys.exit(__doc__)
    yaml_dir, new, base = args
    local = "--no-armbian-repo" in sys.argv
    for name in sorted(os.listdir(yaml_dir)):
        if not name.endswith(".yaml"):
            continue
        path = os.path.join(yaml_dir, name)
        with open(path) as f:
            data = yaml.safe_load(f)
        if data is None:
            continue
        changed = add_release(data, new, base)
        if local:
            changed |= no_armbian_repo(name, data, new)
        if changed:
            with open(path + ".new", "w") as f:
                yaml.safe_dump(data, f, sort_keys=False, default_flow_style=False)
            os.replace(path + ".new", path)
            print(f"{name}: {new} added (from {base})")


if __name__ == "__main__":
    main()
