#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Switch the Orange Pi Zero2's power through a Meross smart plug (MSS110), LAN only.

  scripts/board-power.py status | on | off | cycle [seconds off, default 10]

Reads MEROSS_IP and MEROSS_KEY from local.env next to scripts/ (never published).
MEROSS_KEY is the account key the plug signs local commands with (sign error 5001 without it).
MEROSS_DEVICE (the plug's name in the Meross app) and MEROSS_UUID bind the script to the board's own
plug: every plug on the account shares the key, and a DHCP change could move another plug onto
MEROSS_IP, so every command first checks the UUID. scripts/meross-get-key.sh fills these in.
Only use 'cycle' when the board answers neither ssh nor serial: cutting power under a mounted
SD-card root risks the filesystem.
"""
import hashlib, json, os, sys, time, urllib.request, uuid

TOP = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))


def env():
    cfg = {}
    with open(os.path.join(TOP, "local.env")) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                cfg[k.strip()] = v.strip().strip('"').strip("'")
    for k in ("MEROSS_DEVICE", "MEROSS_UUID", "MEROSS_IP", "MEROSS_KEY"):
        if not cfg.get(k):
            sys.exit(f"board-power: {k} missing in local.env (run scripts/meross-get-key.sh)")
    return cfg["MEROSS_IP"], cfg["MEROSS_KEY"], (cfg["MEROSS_DEVICE"], cfg["MEROSS_UUID"].lower())


def call(ip, key, method, namespace, payload):
    mid, ts = uuid.uuid4().hex, int(time.time())
    msg = {"header": {"from": "", "messageId": mid, "method": method, "namespace": namespace,
                      "payloadVersion": 1, "timestamp": ts,
                      "sign": hashlib.md5((mid + key + str(ts)).encode()).hexdigest()},
           "payload": payload}
    req = urllib.request.Request(f"http://{ip}/config", json.dumps(msg).encode(),
                                 {"Content-Type": "application/json"})
    r = json.loads(urllib.request.urlopen(req, timeout=5).read())
    if r.get("header", {}).get("method") == "ERROR":
        sys.exit(f"board-power: plug refused {namespace}: {r.get('payload')}")
    return r.get("payload", {})


def state(ip, key, dev):
    a = call(ip, key, "GET", "Appliance.System.All", {})["all"]
    got = a["system"]["hardware"].get("uuid", "").lower()
    if got != dev[1]:
        sys.exit(f"board-power: plug at {ip} is uuid {got}, not '{dev[0]}' ({dev[1]}); refusing")
    t = a["digest"]["togglex"]
    return t[0]["onoff"] if isinstance(t, list) else t["onoff"]


def switch(ip, key, dev, on):
    state(ip, key, dev)  # identity check before switching anything
    call(ip, key, "SET", "Appliance.Control.ToggleX", {"togglex": {"channel": 0, "onoff": int(on)}})
    for _ in range(10):
        if state(ip, key, dev) == int(on):
            return
        time.sleep(0.5)
    sys.exit(f"board-power: plug did not report {'on' if on else 'off'}")


def main(a):
    if not a or a[0] not in ("status", "on", "off", "cycle"):
        sys.exit(__doc__)
    ip, key, dev = env()
    if a[0] == "status":
        print("on" if state(ip, key, dev) else "off")
    elif a[0] in ("on", "off"):
        switch(ip, key, dev, a[0] == "on")
        print(a[0])
    else:
        secs = float(a[1]) if len(a) > 1 else 10
        switch(ip, key, dev, False)
        print(f"off, waiting {secs:g} s", flush=True)
        time.sleep(secs)
        switch(ip, key, dev, True)
        print("on")


if __name__ == "__main__":
    main(sys.argv[1:])
