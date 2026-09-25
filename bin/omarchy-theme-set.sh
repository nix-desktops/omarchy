# Switch theme (omarchy-theme-set, NixOS edition). Upstream copies the theme
# into ~/.local/state/omarchy/current and restarts every app; here the pick
# is recorded in the host's theme.json (omarchy.stateDir) and the system rebuilds, which
# relinks ~/.local/state/omarchy/current/theme and restarts the shell with
# the new colors (the omarchy Home Manager module).
#
#   omarchy-theme-set            pick from Omarchy's theme switcher
#   omarchy-theme-set <name>     switch directly
theme_json="$OMARCHY_STATE/theme.json"

target="${1-}"
if [ -z "$target" ]; then
  target=$(omarchy-theme-switcher) || exit 0
  [ -z "$target" ] && exit 0
fi

if [ ! -d "$HOME/.config/omarchy/themes/$target" ]; then
  echo "Unknown theme '$target'. Install community themes with omarchy-theme-install." >&2
  exit 1
fi

if [ "$(jq -r '.theme' "$theme_json")" = "$target" ]; then
  omarchy-notification-send -g 󰸌 "Theme" "'$target' is already active"
  exit 0
fi

tmp=$(mktemp)
jq --arg t "$target" '.theme = $t' "$theme_json" >"$tmp"
mv "$tmp" "$theme_json"

exec omarchy-launch-floating-terminal-with-presentation omarchy-nixos-rebuild
