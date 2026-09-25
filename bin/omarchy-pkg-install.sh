# Declarative package install (omarchy-pkg-install, NixOS edition): add
# nixpkgs attributes to the host's apps.json (omarchy.stateDir) and rebuild.
#
#   omarchy-pkg-install              search nixpkgs and pick (terminal)
#   omarchy-pkg-install <attr>...    add these attributes (menu entries)
apps_json="$OMARCHY_STATE/apps.json"

if [ $# -eq 0 ]; then
  query=$(gum input --placeholder "Search nixpkgs..." --prompt "󰉉 ") || exit 0
  [ -z "$query" ] && exit 0

  echo ":: Searching nixpkgs for '$query' (first run can take a moment)..."
  # nix search exits non-zero on zero matches; keep going to say so.
  results=$(nix search nixpkgs "$query" --json 2>/dev/null |
    jq -r 'to_entries[] | (.key | sub("^legacyPackages\\.[^.]+\\.";"")) + "\t" + (.value.description // "")' || true)
  if [ -z "$results" ]; then
    echo "No packages matched '$query'."
    exit 1
  fi

  choice=$(fzf --delimiter='\t' --with-nth=1,2 --prompt="install > " \
    --header="Enter installs declaratively (edits apps.json + rebuild)" <<<"$results") || exit 0
  set -- "$(cut -f1 <<<"$choice")"
  [ -z "$1" ] && exit 0
fi

new=()
for attr in "$@"; do
  if jq -e --arg p "$attr" '.packages | index($p)' "$apps_json" >/dev/null; then
    echo "'$attr' is already installed."
  else
    new+=("$attr")
  fi
done
[ "${#new[@]}" -eq 0 ] && exit 0

tmp=$(mktemp)
jq --args '.packages = (.packages + $ARGS.positional | sort | unique)' "${new[@]}" <"$apps_json" >"$tmp"
mv "$tmp" "$apps_json"
echo ":: Added ${new[*]} to apps.json"

omarchy-nixos-rebuild
