# The plugin survey's batch script (the NixOS test script of vm.nix; runs
# in the test driver on the host, `machine` is the VM). For every plugin of
# the batch (SURVEY_BATCH, from survey.py), in turn:
#   copy its clone into the VM, `omarchy plugin add <repo> --yes --enable`
#   as the user, wait, then record: listed and enabled, on the bar (and its
#   size), QML errors and warnings in the shell's journal that name it, a
#   screenshot (the widget, or the panel/overlay summoned), whether the
#   shell crashed; then `omarchy plugin remove` it, delete its copies, and
#   restart the shell when it died, or when the plugin was a replacement bar
#   or changes the session (lock screen, desktop background layer).
# A plugin from the flake's registry (p["registry"]) is declared in the VM
# (vm.nix): it's there and switched on from boot, so it isn't added or
# removed, and its journal lines are read from the shell's start.
# The plugin is found by its manifest id (what `plugin add` installs it as),
# which a few catalog entries don't match.
# One JSON line per plugin goes to $SURVEY_OUT/runtime.jsonl, and a "start"
# line to progress.jsonl before each, so a VM that dies mid-plugin still
# names the plugin that killed it.
import json
import os
import re
import shlex
import time

batch = json.load(open(os.environ["SURVEY_BATCH"]))
out = os.environ["SURVEY_OUT"]
settle = batch.get("settle", 5)
timeout = batch.get("timeout", 60)
os.makedirs(os.path.join(out, "screenshots"), exist_ok=True)

home = "/home/omarchy"
env = "XDG_RUNTIME_DIR=/run/user/1000 HYPRLAND_INSTANCE_SIGNATURE=$(ls /run/user/1000/hypr | head -1)"
# The VM draws in software: a plugin reload can keep the shell busy past
# omarchy-shell's 2 s IPC timeout.
session = env + (" WAYLAND_DISPLAY=$(cd /run/user/1000 && ls wayland-? | head -1)"
                 " DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus OMARCHY_SHELL_IPC_TIMEOUT=20s")
unit = "systemctl --user -M omarchy@"
ERROR_WORDS = ("rror", "failed", "not installed", "not a type", "is not defined", "Cannot", "Unable",
               "is not a function", "undefined", "Type error", "unavailable", "No such file")
# First-run noise, not failures: Quickshell's FileView reading a state or
# cache file a plugin writes later, and an image that isn't there yet.
FILEVIEW_MISSING = re.compile(r"FileView .*Read of (\S+) failed: File does not exist")
CANNOT_OPEN = re.compile(r"Cannot open: (?:file://)?(/\S+)")
URL = re.compile(r"(?:file|qrc|https?)://\S+")


def append(name, record):
    with open(os.path.join(out, name), "a") as f:
        f.write(json.dumps(record) + "\n")


def as_user(cmd, t=None):
    status, output = machine.execute(
        f"su - omarchy -c {shlex.quote(session + ' ' + cmd)}", timeout=t or timeout)
    return status, output


def shell_state():
    status, pid = machine.execute(f"{unit} show -p MainPID --value omarchy-shell.service")
    active = machine.execute(f"{unit} is-active omarchy-shell.service")[0] == 0
    return pid.strip(), active


def wait_shell(t=120):
    machine.wait_until_succeeds(f"{unit} is-active omarchy-shell.service", timeout=t)
    machine.wait_until_succeeds(
        f"su - omarchy -c {shlex.quote(session + ' omarchy-shell shell listPlugins')} | grep -q omarchy.clock", timeout=t)


def ipc_json(cmd):
    status, output = as_user(cmd, 30)
    if status != 0:
        return None
    try:
        return json.loads(output)
    except ValueError:
        return None


def classify(lines, names):
    """Journal lines naming the plugin → (errors, warnings). The plugin's
    names and file URLs are taken out before looking for error words (ids
    like mirror-x contain "rror"); DEBUG lines (console.log, the shell's
    own "reloading <id>") are never errors."""
    errors, warnings = [], []
    for l in lines:
        body = l.strip()
        if body.startswith("DEBUG"):
            continue
        m = FILEVIEW_MISSING.search(l)
        if m and m.group(1).startswith((home + "/", "/tmp/", "/run/user/")):
            warnings.append(l[:400])
            continue
        m = CANNOT_OPEN.search(l)
        if m and machine.execute(f"test -e {shlex.quote(m.group(1))}")[0] == 0:
            warnings.append(l[:400])  # there now: it was written a moment later
            continue
        stripped: str = URL.sub("", l)
        for n in sorted(names, key=len, reverse=True):
            stripped = stripped.replace(str(n), "")
        if any(w in stripped for w in ERROR_WORDS):
            errors.append(l[:400])
        elif "WARN" in l or "warning" in l.lower():
            warnings.append(l[:400])
    return errors[:20], warnings[:20]


def restart_shell(t=180):
    machine.execute(f"{unit} restart omarchy-shell.service")
    wait_shell(t)
    # The bar comes up a moment after the shell answers.
    for _ in range(20):
        if ipc_json("omarchy-shell shell debugBarGeometry"):
            return True
        machine.sleep(2)
    return False


start = time.time()
start_all()
machine.wait_for_unit("home-manager-omarchy.service")
wait_shell(240)
machine.wait_until_succeeds(f"su - omarchy -c {shlex.quote(env + ' hyprctl version')}", timeout=120)
machine.sleep(5)
online = machine.execute("timeout 20 curl -sSfI https://github.com >/dev/null")[0] == 0
append("batch.jsonl", {"event": "booted", "seconds": round(time.time() - start, 1), "online": online})
machine.screenshot(os.path.join(out, "screenshots", "_desktop"))

for p in batch["plugins"]:
    pid, slug, kinds = p["id"], p["slug"], p.get("kinds") or []
    # What `plugin add` installs it as; the catalog's id can differ.
    mid = p.get("manifestId") or pid
    t0 = time.time()
    append("progress.jsonl", {"id": pid, "phase": "start"})
    rec = {"id": pid, "manifestId": mid, "slug": slug}
    try:
        # Idle is off (vm.nix); a plugin before this one may still have
        # locked the session.
        rec["lockedBefore"] = (as_user("omarchy-shell lock isLocked", 30)[1].strip() or None)
        before_pid, _ = shell_state()
        since = machine.succeed("date +%s.%N").strip()
        if p.get("registry"):
            since = "0"
            rec["add"] = {"status": 0, "output": "declared: omarchy.plugins.<id>.enable (pkgs/plugins)"}
        else:
            src = f"/tmp/survey/{slug}"
            machine.succeed(f"rm -rf {src} && mkdir -p /tmp/survey")
            machine.copy_from_host(p["path"], src)
            machine.succeed(f"chown -R omarchy:users {src}")
            status, output = as_user(f"timeout {timeout} omarchy plugin add {src} --yes --enable 2>&1")
            rec["add"] = {"status": status, "output": output[-1500:]}
            machine.sleep(settle)

        listed = ipc_json("omarchy plugin list --json") or []
        entry = next((x for x in listed if x.get("id") == mid), None)
        rec["listed"] = entry is not None
        rec["enabled"] = bool(entry and entry.get("enabled"))
        # The shell can be slow to answer on a busy host, and a widget can
        # take a moment to get its slot: ask again before calling it absent.
        slot, geometry = None, None
        for attempt in range(4):
            geometry = ipc_json("omarchy-shell shell debugBarGeometry")
            slot = next((g for g in geometry or [] if g.get("id") == mid), None)
            if slot:
                break
            machine.sleep(3)
        rec["bar"] = slot
        rec["barQuery"] = "ok" if geometry is not None else "failed"

        # The picture: the widget on the bar, or the panel/overlay/menu
        # opened.
        shot = None
        if slot and slot.get("width", 0) > 0 and slot.get("height", 0) > 0:
            pad = 6
            x, y = max(0, slot["x"] - pad), max(0, slot["y"] - pad)
            w, h = slot["width"] + 2 * pad, slot["height"] + 2 * pad
            if as_user(f"grim -g \"{x},{y} {w}x{h}\" /tmp/shot.png", 30)[0] == 0:
                shot = "widget"
        if not shot and any(k in kinds for k in ("panel", "overlay", "menu")):
            r = as_user(f"omarchy-shell shell summon {shlex.quote(mid)} '{{}}'", 30)
            rec["summon"] = r[1].strip()[-200:]
            machine.sleep(3)
            if as_user("grim /tmp/shot.png", 30)[0] == 0:
                shot = "opened"
            as_user(f"omarchy-shell shell hide {shlex.quote(mid)}", 30)
        if not shot and "bar" in kinds:
            if as_user("grim /tmp/shot.png", 30)[0] == 0:
                shot = "screen"
        if shot:
            name = f"{slug}.png"
            machine.succeed(f"mv /tmp/shot.png /tmp/{name}")
            machine.copy_from_vm(f"/tmp/{name}", "screenshots")
            machine.succeed(f"rm -f /tmp/{name}")
            rec["screenshot"] = f"screenshots/{name}"
            rec["screenshotKind"] = shot

        # The shell's journal since it was added: lines naming the plugin.
        _, journal = machine.execute(
            f"journalctl --no-pager -o cat --since @{since} _SYSTEMD_USER_UNIT=omarchy-shell.service")
        journal = re.sub(r"\x1b\[[0-9;]*m", "", journal)
        mine = [l for l in journal.splitlines()
                if pid in l or mid in l or f"/plugins/{mid}/" in l or f"/survey/{slug}/" in l]
        rec["errors"], rec["warnings"] = classify(mine, {pid, mid, slug})
        rec["log"] = [l[:300] for l in mine][:40]

        after_pid, active = shell_state()
        rec["crashed"] = (not active) or (after_pid != before_pid)
        if rec["crashed"]:
            _, rec["crashLog"] = machine.execute(
                f"journalctl --no-pager -o cat --since @{since} _SYSTEMD_USER_UNIT=omarchy-shell.service | tail -40")
            rec["crashLog"] = rec["crashLog"][-4000:]
    except Exception as e:  # noqa: BLE001 — record and go on
        rec["harnessError"] = repr(e)[:500]

    # Clean up for the next one: remove it, delete every copy (the VM's disk
    # is small), and restart the shell when it died or the plugin changed
    # more than itself. Upstream's shell.qml leaves `shell.bar` null after a
    # replacement bar is removed (pluginBarLoader's onActiveChanged clears it
    # after the default bar's onLoaded set it), so every later widget would
    # get no slot; a lock screen or background layer can outlive its plugin.
    try:
        q = shlex.quote(mid)
        if p.get("registry"):
            pass  # declared: stays for the whole batch
        elif as_user(f"timeout {timeout} omarchy plugin remove {q} --yes 2>&1")[0] != 0:
            as_user(f"omarchy-shell shell setPluginEnabled {q} false", 30)
            as_user("omarchy-shell shell rescanPlugins", 30)
        plugins = f"{home}/.config/omarchy/plugins"
        mine_dir = "" if p.get("registry") else f"{plugins}/{q} {plugins}/.{q}.bak.* "
        machine.execute(f"rm -rf /tmp/survey/{shlex.quote(slug)} {mine_dir}"
                        f"{plugins}/.add.tmp.* /tmp/shot.png")
        _, active = shell_state()
        if "bar" in kinds:
            machine.sleep(2)
            rec["barAfterRemove"] = len(ipc_json("omarchy-shell shell debugBarGeometry") or [])
        if not active or rec.get("crashed") or "bar" in kinds or p.get("session"):
            rec["restarted"] = True
            if not restart_shell():
                rec["cleanupError"] = "no bar after restarting the shell"
        else:
            wait_shell(120)
        rec["diskFree"] = machine.execute("df --output=avail -BM / | tail -1")[1].strip()
    except Exception as e:  # noqa: BLE001
        rec["cleanupError"] = repr(e)[:500]
        try:
            restart_shell()
        except Exception as e2:  # noqa: BLE001
            rec["cleanupError"] += " / " + repr(e2)[:300]
            rec["seconds"] = round(time.time() - t0, 1)
            append("runtime.jsonl", rec)
            raise
    rec["seconds"] = round(time.time() - t0, 1)
    append("runtime.jsonl", rec)

append("batch.jsonl", {"event": "done", "seconds": round(time.time() - start, 1)})
