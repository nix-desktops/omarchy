# Select and set the system timezone (omarchy-menu-timezone, NixOS edition).
# NixOS lets timedatectl change the zone only while `time.timeZone` is null;
# the omarchy NixOS module writes /etc/omarchy/time-zone when the config sets
# it, and then the zone is changed there, not here.
#
#   omarchy-menu-timezone            pick from the list
#   omarchy-menu-timezone <zone>     set this zone (e.g. Europe/Amsterdam)
declared=/etc/omarchy/time-zone
if [ -f "$declared" ]; then
  zone=$(cat "$declared")
  echo "The time zone is set in the NixOS config (time.timeZone = \"$zone\")." >&2
  omarchy-notification-send -u normal "Timezone is set in your NixOS config" \
    "time.timeZone = \"$zone\". Change it there and rebuild, or set it to null to pick it from this menu." || true
  exit 1
fi

timezone="${1-}"
if [ -z "$timezone" ]; then
  timezone=$(timedatectl list-timezones | omarchy-menu-select "Set timezone" -- --width 520 --maxheight 520) || exit 1
  [ -z "$timezone" ] && exit 1
fi
# Through polkit (the shell is the agent), not sudo: the menu has no terminal.
timedatectl set-timezone "$timezone"
omarchy-shell -q omarchy.clock refresh || true
omarchy-notification-send "Timezone is now set to $timezone" || true
