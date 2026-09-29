#!/usr/bin/env python3
"""Lay out declared plugins' systemd user units as ~/.config/systemd/user.

  plugin-user-units.py <units.json> <out> <mkdir>

units.json: [{"name": "x.service", "source": "/nix/store/…", "wantedBy": null | [...]}].
For each unit: <out>/<name> (a drop-in keeps its <unit>.d/ directory), and
<out>/<target>.wants/<name> (.requires/, .upholds/) links for the targets
that pull it in: its [Install] section's WantedBy=/RequiredBy=/UpheldBy=,
Alias= links, unless wantedBy is given (then those targets' .wants only).
A [Service] with ReadWritePaths= gets `ExecStartPre=-+<mkdir> -p -m 0700 <paths>`
first: systemd won't set up the unit's namespace (status 226/NAMESPACE)
while one of them is missing, and "+" runs the mkdir outside it.
"""
import json
import os
import re
import sys

units_json, out, mkdir = sys.argv[1:4]
with open(units_json) as f:
    units = json.load(f)


def sections(text):
    """(section, key, value) for each assignment, continuation lines joined."""
    sec = None
    lines = text.splitlines()
    i = 0
    while i < len(lines):
        line = lines[i].strip()
        i += 1
        if not line or line[0] in "#;":
            continue
        if line.startswith("[") and line.endswith("]"):
            sec = line[1:-1]
            continue
        while line.endswith("\\") and i < len(lines):
            line = line[:-1] + " " + lines[i].strip()
            i += 1
        if "=" in line:
            k, v = line.split("=", 1)
            yield sec, k.strip(), v.strip()


def link(path, target):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if os.path.lexists(path):
        os.remove(path)
    os.symlink(target, path)


for u in units:
    name = u["name"]
    if name.startswith("/") or ".." in name.split("/"):
        sys.exit(f"{name}: a unit name, relative to ~/.config/systemd/user")
    with open(u["source"]) as f:
        text = f.read()
    assigns = list(sections(text))
    paths = []
    for sec, k, v in assigns:
        if sec == "Service" and k == "ReadWritePaths":
            if not v:
                paths = []  # an empty assignment resets the list
                continue
            # "-" marks one that may be missing: systemd skips it, no mkdir needed.
            paths += [p.lstrip("+") for p in v.split() if not p.startswith("-")]
    if paths:
        pre = f"ExecStartPre=-+{mkdir} -p -m 0700 " + " ".join(paths)
        text, n = re.subn(r"^\[Service\][ \t]*$", lambda m: m.group(0) + "\n" + pre, text, count=1, flags=re.M)
        assert n == 1
    dest = os.path.join(out, name)
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    with open(dest, "w") as f:
        f.write(text)

    if "/" in name:
        continue  # a drop-in: nothing to enable
    base = name
    template = re.match(r"^(.+)@(\.[a-z]+)$", name)
    if u.get("wantedBy") is not None:
        wants = [("wants", t) for t in u["wantedBy"]]
        aliases = []
    else:
        wants, aliases = [], []
        default_instance = None
        for sec, k, v in assigns:
            if sec != "Install":
                continue
            if k in ("WantedBy", "RequiredBy", "UpheldBy"):
                kind = {"WantedBy": "wants", "RequiredBy": "requires", "UpheldBy": "upholds"}[k]
                wants += [(kind, t) for t in v.split()]
            elif k == "Alias":
                aliases += v.split()
            elif k == "DefaultInstance":
                default_instance = v
        if template:
            # A template is enabled as its DefaultInstance, like systemctl does.
            if not default_instance:
                wants = []
            else:
                base = f"{template.group(1)}@{default_instance}{template.group(2)}"
    for kind, target in wants:
        link(os.path.join(out, f"{target}.{kind}", base), f"../{name}")
    for alias in aliases:
        link(os.path.join(out, alias), name)
