#!/usr/bin/env python3
# Declared plugins (omarchy.plugins) switched on the way upstream's shell
# records it in shell.json (PluginRegistry.setEnabled): a bar widget as an
# entry in bar.layout.<section> (after the section's anchor widget, as the
# shell places one), a replacement bar as bar.id, anything else as an entry
# in plugins[]. A third-party plugin is on exactly when its id is there.
#
#   defaults <declared.json> <shell.json>
#       At package build time: every declared plugin into the package's
#       default shell.json, which the shell uses while the user has no
#       ~/.config/omarchy/shell.json of their own.
#
#   activate <declared.json> <user shell.json> <state.json>
#       At activation, for a user shell.json (the shell writes one as soon
#       as anything is changed from the menu or `omarchy plugin`): a plugin
#       declared since the last activation is switched on once; one that
#       is no longer declared is switched off. What the user does in
#       between (switching a declared plugin off, moving it on the bar) is
#       theirs and stays. state.json remembers which declared plugins were
#       switched on.
#
# declared.json: [{"id", "section" (or null), "manifest" (path)}]
import json
import os
import sys
import tempfile

ANCHORS = {"left": "omarchy.workspaces", "center": "omarchy.weather", "right": "omarchy.tray"}


def entry_id(entry):
    return entry.get("id") if isinstance(entry, dict) else entry


def shape(cfg):
    bar = cfg.setdefault("bar", {})
    if not isinstance(bar, dict):
        bar = cfg["bar"] = {}
    layout = bar.setdefault("layout", {})
    if not isinstance(layout, dict):
        layout = bar["layout"] = {}
    for s in ("left", "center", "right"):
        if not isinstance(layout.get(s), list):
            layout[s] = []
    if not isinstance(cfg.get("plugins"), list):
        cfg["plugins"] = []
    return cfg


def referenced(cfg, pid):
    bar = cfg.get("bar") if isinstance(cfg.get("bar"), dict) else {}
    if bar.get("id") == pid:
        return True
    layout = bar.get("layout") if isinstance(bar.get("layout"), dict) else {}
    for s in ("left", "center", "right"):
        if any(entry_id(e) == pid for e in layout.get(s) or []):
            return True
    return any(entry_id(e) == pid for e in cfg.get("plugins") or [])


def enable(cfg, pid, manifest_path, section):
    try:
        with open(manifest_path) as f:
            manifest = json.load(f)
    except (OSError, ValueError):
        manifest = {}
    kinds = manifest.get("kinds") or []
    shape(cfg)
    if "bar" in kinds:
        cfg["bar"]["id"] = pid
    elif "bar-widget" in kinds:
        bw = manifest.get("barWidget") if isinstance(manifest.get("barWidget"), dict) else {}
        section = section or bw.get("defaultSection")
        if section not in ("left", "center", "right"):
            section = "center"
        entries = cfg["bar"]["layout"][section]
        at = len(entries)
        for i, e in enumerate(entries):
            if entry_id(e) == ANCHORS[section]:
                at = i + 1
                break
        entries.insert(at, {"id": pid})
    else:
        cfg["plugins"].append({"id": pid})


def disable(cfg, pid):
    bar = cfg.get("bar")
    if isinstance(bar, dict):
        if bar.get("id") == pid:
            del bar["id"]
        layout = bar.get("layout")
        if isinstance(layout, dict):
            for s in ("left", "center", "right"):
                if isinstance(layout.get(s), list):
                    layout[s] = [e for e in layout[s] if entry_id(e) != pid]
    if isinstance(cfg.get("plugins"), list):
        cfg["plugins"] = [e for e in cfg["plugins"] if entry_id(e) != pid]


def write_json(path, data):
    d = os.path.dirname(path) or "."
    os.makedirs(d, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".shell.json.")
    with os.fdopen(fd, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    os.chmod(tmp, 0o644)
    os.replace(tmp, path)


def main(argv):
    mode = argv[0]
    with open(argv[1]) as f:
        declared = json.load(f)
    if mode == "defaults":
        path = argv[2]
        with open(path) as f:
            cfg = json.load(f)
        for d in declared:
            if not referenced(cfg, d["id"]):
                enable(cfg, d["id"], d["manifest"], d.get("section"))
        with open(path, "w") as f:
            json.dump(cfg, f, indent=2)
            f.write("\n")
        return 0

    user, state_path = argv[2], argv[3]
    try:
        with open(state_path) as f:
            applied = set(json.load(f).get("enabled", []))
    except (OSError, ValueError):
        applied = set()
    ids = [d["id"] for d in declared]
    cfg = None
    if os.path.exists(user):
        try:
            with open(user) as f:
                cfg = json.load(f)
            if not isinstance(cfg, dict) or cfg.get("version") != 1:
                cfg = None  # the shell ignores it too (uses the defaults)
        except (OSError, ValueError):
            cfg = None
    if cfg is not None:
        changed = False
        for d in declared:
            if d["id"] not in applied and not referenced(cfg, d["id"]):
                enable(cfg, d["id"], d["manifest"], d.get("section"))
                print(f"omarchy: switched on the plugin {d['id']} in {user}")
                changed = True
        for pid in sorted(applied - set(ids)):
            if referenced(cfg, pid):
                disable(cfg, pid)
                print(f"omarchy: switched off the plugin {pid} (no longer declared) in {user}")
                changed = True
        if changed:
            write_json(user, cfg)
    # Without a user shell.json the package's defaults carry the declared
    # plugins; the shell copies them into the file it writes later.
    write_json(state_path, {"enabled": sorted(ids)})
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
