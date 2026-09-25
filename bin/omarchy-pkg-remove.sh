# Remove menu-installed packages (omarchy-pkg-remove, NixOS edition): drop
# attributes from the host's apps.json (omarchy.stateDir) and rebuild. Packages declared
# elsewhere in the config repo are not managed here.
#
#   omarchy-pkg-remove               pick from apps.json (terminal)
#   omarchy-pkg-remove <attr>...     remove these attributes
apps_json="$OMARCHY_STATE/apps.json"

if [ $# -eq 0 ]; then
  mapfile -t installed < <(jq -r '.packages[]' "$apps_json")
  if [ "${#installed[@]}" -eq 0 ]; then
    echo "No menu-installed packages to remove."
    exit 0
  fi
  choice=$(printf '%s\n' "${installed[@]}" | gum choose --header "Remove package (esc to cancel)") || exit 0
  [ -z "$choice" ] && exit 0
  set -- "$choice"
fi

tmp=$(mktemp)
jq --args '.packages -= $ARGS.positional' "$@" <"$apps_json" >"$tmp"
mv "$tmp" "$apps_json"
echo ":: Removed $* from apps.json"

omarchy-nixos-rebuild
