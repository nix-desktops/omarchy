# True when every named package is installed. Used by the menu's
# installed/not-installed guards. A name (a nixpkgs attribute, or an Arch
# name as upstream passes it) counts as installed when its nixpkgs
# attribute is in the host's apps.json (omarchy.stateDir; see
# omarchy-pkg-attr), when the pacman shim finds it among the system's and
# the user's packages (declared anywhere in the config; omarchy.pacmanShim),
# or when a command of that name is on PATH.
apps_json="$OMARCHY_STATE/apps.json"
has_pacman=
command -v pacman >/dev/null 2>&1 && has_pacman=1
for pkg in "$@"; do
  attr=$(omarchy-pkg-attr "$pkg")
  jq -e --arg p "$attr" '.packages | index($p)' "$apps_json" >/dev/null 2>&1 && continue
  [[ -n $has_pacman ]] && pacman -Q -- "$pkg" >/dev/null 2>&1 && continue
  command -v "$pkg" >/dev/null 2>&1 && continue
  exit 1
done
