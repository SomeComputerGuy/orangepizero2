#!/usr/bin/env python3
"""Drive the host's wlo1 through wpa_supplicant D-Bus (no sudo; run via `sg netdev`).

usage: sg netdev -c "python3 -I wifi-host.py <cmd> [args]"
  scan [substr]                  active scan, list BSSs (ssid substring filter)
  sta <ssid> [freq|-] [k=v ...]  connect as WPA2-PSK client (PSK from PSK_FILE), extra network opts
  ap <ssid> <freq> [open|k=v]    start a WPA2-PSK (or open) AP (mode 2)
  state                          State + CurrentBSS + SignalPoll
  wait <state> [timeout]         wait for State == <state>
  down                           RemoveAllNetworks (disconnect)
"""
import sys, time
import dbus

PSK_FILE = "/home/aruni/.claude/jobs/d2570224/tmp/wifi-psk"
S = "fi.w1.wpa_supplicant1"
bus = dbus.SystemBus()
root = dbus.Interface(bus.get_object(S, "/fi/w1/wpa_supplicant1"), S)
ipath = root.GetInterface("wlo1")
iobj = bus.get_object(S, ipath)
iface = dbus.Interface(iobj, S + ".Interface")
props = dbus.Interface(iobj, dbus.PROPERTIES_IFACE)


def psk():
    return open(PSK_FILE).read().strip()


def bss_info(p):
    b = dbus.Interface(bus.get_object(S, p), dbus.PROPERTIES_IFACE)
    a = b.GetAll(S + ".BSS")
    ssid = bytes(a["SSID"]).decode("utf-8", "replace")
    bssid = ":".join("%02x" % x for x in a["BSSID"])
    return ssid, bssid, int(a["Frequency"]), int(a["Signal"]), int(a.get("Age", 0))


def cmd_scan(flt=""):
    iface.Scan({"Type": "active"})
    time.sleep(6)
    for p in props.Get(S + ".Interface", "BSSs"):
        try:
            ssid, bssid, f, sig, age = bss_info(p)
        except dbus.DBusException:
            continue
        if flt in ssid:
            print(f"{f:5d} {sig:4d}dBm age={age:3d} {bssid} {ssid!r}")


def cmd_ies(flt):
    """dump HT/VHT/DS/country elements of BSSs whose SSID contains flt"""
    names = {3: "DS", 7: "Country", 45: "HTCap", 61: "HTOper", 191: "VHTCap", 192: "VHTOper", 0xff: "Ext"}
    for p in props.Get(S + ".Interface", "BSSs"):
        b = dbus.Interface(bus.get_object(S, p), dbus.PROPERTIES_IFACE)
        a = b.GetAll(S + ".BSS")
        ssid = bytes(a["SSID"]).decode("utf-8", "replace")
        if flt not in ssid:
            continue
        print(ssid, int(a["Frequency"]), "MHz")
        ie = bytes(a["IEs"])
        i = 0
        while i + 2 <= len(ie):
            eid, ln = ie[i], ie[i + 1]
            body = ie[i + 2:i + 2 + ln]
            if eid in names:
                extra = ""
                if eid == 61:
                    extra = " primary=%d secoff=%d sta_chw=%d" % (body[0], body[1] & 3, (body[1] >> 2) & 1)
                if eid == 192:
                    extra = " chw=%d seg0=%d seg1=%d" % (body[0], body[1], body[2])
                if eid == 7:
                    extra = " " + body[:3].decode("ascii", "replace")
                print("  %-8s %s%s" % (names[eid], body.hex(), extra))
            i += 2 + ln


def cmd_down():
    iface.RemoveAllNetworks()
    print("removed")


def add(cfg):
    iface.RemoveAllNetworks()
    n = iface.AddNetwork(dbus.Dictionary(cfg, signature="sv"))
    iface.SelectNetwork(n)
    print("selected", n)


def cmd_sta(ssid, freq=None, *extra):
    """extra: key=value network options, e.g. disable_ht=1 disable_vht=1"""
    cfg = {"ssid": ssid, "psk": psk(), "key_mgmt": "WPA-PSK", "scan_ssid": dbus.Int32(1)}
    if freq and freq != "-":
        cfg["scan_freq"] = str(freq)
        cfg["freq_list"] = str(freq)
    for kv in extra:
        k, v = kv.split("=", 1)
        cfg[k] = dbus.Int32(int(v)) if v.lstrip("-").isdigit() else v
    add(cfg)


def cmd_ap(ssid, freq, *extra):
    """extra: 'open' for an unencrypted AP, or key=value network options"""
    cfg = {"ssid": ssid, "psk": psk(), "key_mgmt": "WPA-PSK", "mode": dbus.Int32(2),
           "frequency": dbus.Int32(int(freq)), "proto": "RSN", "pairwise": "CCMP", "group": "CCMP"}
    for kv in extra:
        if kv == "open":
            for k in ("psk", "proto", "pairwise", "group"):
                cfg.pop(k)
            cfg["key_mgmt"] = "NONE"
            continue
        k, v = kv.split("=", 1)
        cfg[k] = dbus.Int32(int(v)) if v.lstrip("-").isdigit() else v
    add(cfg)


def cmd_state():
    st = props.Get(S + ".Interface", "State")
    print("State:", st)
    cur = props.Get(S + ".Interface", "CurrentBSS")
    if cur != "/":
        try:
            print("CurrentBSS:", bss_info(cur))
        except dbus.DBusException:
            pass
    try:
        sp = iface.SignalPoll()
        print("SignalPoll:", {str(k): (int(v) if isinstance(v, (dbus.Int32, dbus.UInt32)) else str(v)) for k, v in sp.items()})
    except dbus.DBusException as e:
        print("SignalPoll:", e.get_dbus_message())


def cmd_wait(want, timeout=30):
    t = time.time() + float(timeout)
    while time.time() < t:
        st = props.Get(S + ".Interface", "State")
        if st == want:
            print("reached", st, "after %.1fs" % (float(timeout) - (t - time.time())))
            return
        time.sleep(0.5)
    print("timeout, state", props.Get(S + ".Interface", "State"))
    sys.exit(1)


if __name__ == "__main__":
    c, *a = sys.argv[1:] or ["state"]
    globals()["cmd_" + c](*a)
