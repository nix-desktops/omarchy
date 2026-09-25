# Remove an installed community theme (omarchy-theme-remove, NixOS
# edition): drop its pin from the host's theme.json (omarchy.stateDir) and rebuild. If it
# is the active theme, switch to tokyo-night (Omarchy's default) first.
# Built-in themes ship with Omarchy and can't be removed.
theme_json="$OMARCHY_STATE/theme.json"

target="${1-}"
if [ -z "$target" ]; then
  mapfile -t rows < <(jq -r '.installed // {} | keys[] | "󰸌\t\(.)"' "$theme_json")
  if [ "${#rows[@]}" -eq 0 ]; then
    omarchy-notification-send -g 󰸌 "Themes" "No community themes installed"
    exit 0
  fi
  target=$(omarchy-menu-select "Remove theme" "${rows[@]}") || exit 0
  [ -z "$target" ] && exit 0
fi

if ! jq -e --arg n "$target" '(.installed // {}) | has($n)' "$theme_json" >/dev/null; then
  echo "'$target' is not an installed community theme." >&2
  exit 1
fi

tmp=$(mktemp)
jq --arg n "$target" '
    del(.installed[$n])
    | if .theme == $n then .theme = "tokyo-night" else . end' "$theme_json" >"$tmp"
mv "$tmp" "$theme_json"

exec omarchy-launch-floating-terminal-with-presentation omarchy-nixos-rebuild
