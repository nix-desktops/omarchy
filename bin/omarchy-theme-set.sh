# Switch theme (omarchy-theme-set, NixOS edition). Live, as upstream: the
# theme is staged into ~/.local/state/omarchy/current and the running shell,
# Hyprland, terminals and apps are retinted by upstream's own omarchy-theme-set
# (kept in the package as libexec/omarchy-theme-set). The pick is also recorded
# in the host's theme.json (omarchy.stateDir), so the next rebuild keeps it
# and brings the parts that are built from it (the browser color policy, the
# palette for host theming such as Stylix) up to date. No rebuild here.
#
#   omarchy-theme-set            pick from Omarchy's theme switcher
#   omarchy-theme-set <name>     switch directly
theme_json="$OMARCHY_STATE/theme.json"
state="$HOME/.local/state/omarchy/current"

target="${1-}"
if [ -z "$target" ]; then
  target=$(omarchy-theme-switcher) || exit 0
  [ -z "$target" ] && exit 0
fi
# Upstream's normalization: display names ("Tokyo Night") to directory names.
target=$(printf '%s' "$target" | sed -E 's/<[^>]+>//g' | tr '[:upper:]' '[:lower:]' | tr ' ' '-')

if [ ! -d "$HOME/.config/omarchy/themes/$target" ]; then
  echo "Unknown theme '$target'. Install community themes with omarchy-theme-install." >&2
  exit 1
fi

if [ "$(cat "$state/theme.name" 2>/dev/null)" = "$target" ] &&
  [ "$(jq -r '.theme' "$theme_json")" = "$target" ]; then
  omarchy-notification-send -g 󰸌 "Theme" "'$target' is already active"
  exit 0
fi

# Recorded first, so a rebuild at any point keeps the pick.
if [ "$(jq -r '.theme' "$theme_json")" != "$target" ]; then
  tmp=$(mktemp)
  jq --arg t "$target" '.theme = $t' "$theme_json" >"$tmp"
  mv "$tmp" "$theme_json"
fi

omarchy_path="${OMARCHY_PATH:-$HOME/.local/share/omarchy}"
status=0
"$omarchy_path/libexec/omarchy-theme-set" "$target" || status=$?

# The background this theme got; the Home Manager activation only resets the
# background when the theme it last saw changes (see omarchyBackground).
mkdir -p "$state"
printf '%s\n' "$target" >"$state/background.theme"
exit "$status"
