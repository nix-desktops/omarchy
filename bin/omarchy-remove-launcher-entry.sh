# Uninstall from the app launcher (omarchy-remove-launcher-entry, NixOS
# edition). Web apps and TUIs are user .desktop files and go the upstream
# way; menu-installed packages leave apps.json; anything else is declared in
# the NixOS config and has to be removed there.
#   omarchy-remove-launcher-entry <desktop-id> <name>
id="${1%.desktop}"
name="${2:-$id}"
entry="$HOME/.local/share/applications/$id.desktop"

if [ -f "$entry" ]; then
  # shellcheck disable=SC2016  # the TUI Exec line holds a literal $TERMINAL
  if grep -qE '^Exec=.*(omarchy-launch-webapp|omarchy-webapp-handler)' "$entry"; then
    exec omarchy-webapp-remove "$name"
  elif grep -qE '^Exec=.*(\$TERMINAL|xdg-terminal-exec).*-e' "$entry"; then
    exec omarchy-tui-remove "$name"
  fi
  rm -f "$entry"
  update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
  exit 0
fi

# Match the desktop id or app name against menu-installed attributes.
apps_json="$OMARCHY_STATE/apps.json"
lower=$(tr '[:upper:]' '[:lower:]' <<<"$id")
attr=$(jq -r --arg a "$lower" '.packages[] | select(ascii_downcase == $a or (split(".") | last | ascii_downcase) == $a)' "$apps_json" | head -n1)
if [ -n "$attr" ]; then
  exec omarchy-launch-floating-terminal-with-presentation "omarchy-pkg-remove '$attr'"
fi

omarchy-notification-send -g 󰭌 "$name" "Installed by the NixOS config; remove it from the config repo."
exit 1
