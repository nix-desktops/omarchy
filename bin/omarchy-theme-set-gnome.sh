# The GNOME interface keys for the current theme (omarchy-theme-set-gnome,
# NixOS edition): the same values as upstream's, written with dconf, which
# needs no GSettings schemas on the search path (NixOS doesn't put them
# there). They land in the user's dconf database, over the system defaults
# the omarchy NixOS module sets from theme.json.
if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
  exit 0
fi

theme_dir="$HOME/.local/state/omarchy/current/theme"
mode=$(omarchy-theme-color --file "$theme_dir/colors.toml" mode 2>/dev/null || echo dark)
if [ "$mode" = "light" ]; then
  dconf write /org/gnome/desktop/interface/color-scheme "'prefer-light'"
  dconf write /org/gnome/desktop/interface/gtk-theme "'Adwaita'"
else
  dconf write /org/gnome/desktop/interface/color-scheme "'prefer-dark'"
  dconf write /org/gnome/desktop/interface/gtk-theme "'Adwaita-dark'"
fi

icons="Yaru-blue"
[ -f "$theme_dir/icons.theme" ] && icons=$(tr -d '[:space:]' <"$theme_dir/icons.theme")
dconf write /org/gnome/desktop/interface/icon-theme "'$icons'"
