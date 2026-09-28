# The plugin survey's batch script (the NixOS test script of vm.nix; runs
# in the test driver on the host, `machine` is the VM). For every plugin of
# the batch (SURVEY_BATCH, from survey.py), in turn:
#   copy its clone into the VM, `omarchy plugin add <repo> --yes --enable`
#   as the user, wait, then record: listed and enabled, on the bar (and its
#   size), QML errors and warnings in the shell's journal that name it, a
#   screenshot (the widget, or the panel/overlay summoned), whether the
#   shell crashed; then `omarchy plugin remove` it (restarting the shell if
#   it died) and go on.
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
    t0 = time.time()
    append("progress.jsonl", {"id": pid, "phase": "start"})
    rec = {"id": pid, "slug": slug}
    try:
        before_pid, _ = shell_state()
        since = machine.succeed("date +%s.%N").strip()
        src = f"/tmp/survey/{slug}"
        machine.succeed(f"rm -rf {src} && mkdir -p /tmp/survey")
        machine.copy_from_host(p["path"], src)
        machine.succeed(f"chown -R omarchy:users {src}")
        status, output = as_user(f"timeout {timeout} omarchy plugin add {src} --yes --enable 2>&1")
        rec["add"] = {"status": status, "output": output[-1500:]}
        machine.sleep(settle)

        listed = ipc_json("omarchy plugin list --json") or []
        entry = next((x for x in listed if x.get("id") == pid), None)
        rec["listed"] = entry is not None
        rec["enabled"] = bool(entry and entry.get("enabled"))
        # The shell can be slow to answer on a busy host, and a widget can
        # take a moment to get its slot: ask again before calling it absent.
        slot, geometry = None, None
        for attempt in range(4):
            geometry = ipc_json("omarchy-shell shell debugBarGeometry")
            slot = next((g for g in geometry or [] if g.get("id") == pid), None)
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
            r = as_user(f"omarchy-shell shell summon {shlex.quote(pid)} '{{}}'", 30)
            rec["summon"] = r[1].strip()[-200:]
            machine.sleep(3)
            if as_user("grim /tmp/shot.png", 30)[0] == 0:
                shot = "opened"
            as_user(f"omarchy-shell shell hide {shlex.quote(pid)}", 30)
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
        mine = [l for l in journal.splitlines() if pid in l or f"/plugins/{pid}/" in l or f"/survey/{slug}/" in l]
        rec["errors"] = [l[:400] for l in mine if any(w in l for w in ERROR_WORDS)][:20]
        rec["warnings"] = len([l for l in mine if "WARN" in l or "warning" in l.lower()])
        rec["log"] = [l[:300] for l in mine][:40]

        after_pid, active = shell_state()
        rec["crashed"] = (not active) or (after_pid != before_pid)
        if rec["crashed"]:
            _, rec["crashLog"] = machine.execute(
                f"journalctl --no-pager -o cat --since @{since} _SYSTEMD_USER_UNIT=omarchy-shell.service | tail -40")
            rec["crashLog"] = rec["crashLog"][-4000:]
    except Exception as e:  # noqa: BLE001 — record and go on
        rec["harnessError"] = repr(e)[:500]

    # Clean up for the next one.
    try:
        if as_user(f"timeout {timeout} omarchy plugin remove {shlex.quote(pid)} --yes 2>&1")[0] != 0:
            as_user(f"omarchy-shell shell setPluginEnabled {shlex.quote(pid)} false", 30)
            machine.execute(f"rm -rf {home}/.config/omarchy/plugins/{shlex.quote(pid)}")
            as_user("omarchy-shell shell rescanPlugins", 30)
        _, active = shell_state()
        if not active or rec.get("crashed"):
            machine.execute(f"{unit} restart omarchy-shell.service")
        wait_shell(120)
    except Exception as e:  # noqa: BLE001
        rec["cleanupError"] = repr(e)[:500]
        try:
            machine.execute(f"{unit} restart omarchy-shell.service")
            wait_shell(180)
        except Exception as e2:  # noqa: BLE001
            rec["cleanupError"] += " / " + repr(e2)[:300]
            rec["seconds"] = round(time.time() - t0, 1)
            append("runtime.jsonl", rec)
            raise
    rec["seconds"] = round(time.time() - t0, 1)
    append("runtime.jsonl", rec)

append("batch.jsonl", {"event": "done", "seconds": round(time.time() - start, 1)})
