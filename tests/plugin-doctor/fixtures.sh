# Small plugins for checks.plugin-doctor, written into $1 (one folder each).
set -eu
d=$1
mk() { mkdir -p "$d/$1"; printf '{"schemaVersion":1,"id":"test.%s","name":"%s","kinds":["bar-widget"]}\n' "$1" "$1" >"$d/$1/manifest.json"; }

# Hints: package-manager commands shown to the user, "pacman" and "aura" as words.
mk hints
cat >"$d/hints/Widget.qml" <<'Q'
import QtQuick
Item {
  property var game: ({ pacman: { x: 0 } })
  Text { text: "Install it with:  sudo pacman -S solaar" }
  Process { command: ["asusctl", "aura", "effect", "static"] }
  // yay -Syu keeps it current
}
Q

# Queries only: fine with the pacman shim.
mk queries
cat >"$d/queries/Widget.qml" <<'Q'
import QtQuick
Item {
  Process { command: ["pacman", "-Qq"] }
  Process { command: ["sh", "-c", "pacman -Q omarchy >/dev/null 2>&1 && echo yes"] }
}
Q

# Installs its dependencies (Arch names), removes them again.
mk installs
cat >"$d/installs/Widget.qml" <<'Q'
import QtQuick
Item { Process { command: ["bash", Qt.resolvedUrl("setup.sh")] } }
Q
cat >"$d/installs/setup.sh" <<'S'
#!/bin/bash
pacman -Q python-gobject >/dev/null 2>&1 || sudo pacman -S --needed --noconfirm python-gobject github-cli qt6-multimedia
disable() { sudo pacman -Rns --noconfirm ydotool; }
S

# A real package manager: updates.
mk updates
cat >"$d/updates/Widget.qml" <<'Q'
import QtQuick
Item { Process { command: ["checkupdates", "--nocolor"] } }
Q

# Commands: a ruby helper, lua, a function from a sourced library, an
# English word, services, a QML module the shell lacks, a required probe.
mk commands
cat >"$d/commands/Widget.qml" <<'Q'
import QtQuick
import QtWebSockets
Item {
  Process { command: [Qt.resolvedUrl("helper.rb")] }
  Process { command: ["bash", Qt.resolvedUrl("run.sh")] }
  Process { command: ["kdeconnect-cli", "-l"] }
}
Q
printf '#!/usr/bin/ruby\nputs 1\n' >"$d/commands/helper.rb"
cat >"$d/commands/run.sh" <<'S'
#!/bin/bash
. "$(dirname "$0")/lib.sh"
command -v jq >/dev/null || die "jq missing"
snapshot a b
lua -e 'print(1)'
msg="only when it runs"
S
cat >"$d/commands/lib.sh" <<'S'
snapshot() { cp "$1" "$2"; }
die() { echo "$*" >&2; exit 1; }
S

# Native-build false positives: dev tooling, a committed bundle, a module
# named setup.py, "pip install" in a docstring.
mk nativefp
cat >"$d/nativefp/Widget.qml" <<'Q'
import QtQuick
Item { Process { command: ["python3", Qt.resolvedUrl("setup.py"), "start"] } }
Q
mkdir -p "$d/nativefp/tools" "$d/nativefp/dist"
printf 'int main(void) { return 0; }\n' >"$d/nativefp/tools/pointer.c"
printf '{"dependencies":{"left-pad":"1"}}\n' >"$d/nativefp/package.json"
printf 'console.log(1)\n' >"$d/nativefp/dist/app.js"
cat >"$d/nativefp/setup.py" <<'P'
"""Stdlib only: no pip install needed."""
import json
print(json.dumps({}))
P

# A real native helper: the QML runs bin/helper, which a Makefile builds.
mk native
cat >"$d/native/Widget.qml" <<'Q'
import QtQuick
Item { Process { command: [Qt.resolvedUrl("bin/helper")] } }
Q
printf 'all:\n\tcc -o bin/helper helper.c\n' >"$d/native/Makefile"
printf 'int main(void) { return 0; }\n' >"$d/native/helper.c"
