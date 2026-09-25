# True when every named package is installed. Used by the menu's
# installed/not-installed guards. A name counts as installed when its
# nixpkgs attribute is in the host's apps.json (omarchy.stateDir; see
# omarchy-pkg-attr) or a command of that name is on PATH (declared
# anywhere else in the config).
apps_json="$OMARCHY_STATE/apps.json"
for pkg in "$@"; do
  attr=$(omarchy-pkg-attr "$pkg")
  jq -e --arg p "$attr" '.packages | index($p)' "$apps_json" >/dev/null 2>&1 && continue
  command -v "$pkg" >/dev/null 2>&1 && continue
  exit 1
done
