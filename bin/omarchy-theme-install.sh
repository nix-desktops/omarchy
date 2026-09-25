# Install a community theme (omarchy-theme-install, NixOS edition). Upstream
# clones the repo into ~/.config/omarchy/themes; here the repo is pinned
# (owner, repo, rev, narHash) in the host's theme.json (omarchy.stateDir), selected, and
# the system rebuilds. lib/theme.nix fetches pinned repos.
#
#   omarchy-theme-install                 pick from the catalog (Omarchy's
#                                         extra themes, community-themes.json)
#   omarchy-theme-install <name>          install a catalog theme by name
#   omarchy-theme-install <github-url>    install any GitHub-hosted theme
theme_json="$OMARCHY_STATE/theme.json"
catalog="$OMARCHY_COMMUNITY_THEMES"

target="${1-}"
if [ -z "$target" ]; then
  mapfile -t rows < <(jq -r --slurpfile state "$theme_json" '
      to_entries[]
      | select(($state[0].installed // {}) | has(.key) | not)
      | "󰸌\t\(.value.title)\t\(.key)"' "$catalog")
  choice=$(omarchy-menu-select "Install theme" "${rows[@]}") || exit 0
  [ -z "$choice" ] && exit 0
  target="${choice##*$'\t'}"
fi

case "$target" in
  https://github.com/* | github.com/*)
    path="${target#*github.com/}"
    path="${path%.git}"
    path="${path%/}"
    owner="${path%%/*}"
    repo="${path#*/}"
    # Omarchy's naming rule: repo name minus omarchy- / -theme, lowercased.
    name=$(printf '%s' "$repo" | sed -E 's/^omarchy-//; s/-theme$//' | tr '[:upper:]' '[:lower:]')
    ;;
  *)
    name="$target"
    owner=$(jq -r --arg n "$name" '.[$n].owner // empty' "$catalog")
    repo=$(jq -r --arg n "$name" '.[$n].repo // empty' "$catalog")
    if [ -z "$owner" ]; then
      echo "'$name' is not in the community catalog; pass a GitHub URL instead." >&2
      exit 1
    fi
    ;;
esac

if ! (LC_ALL=C; [[ $name =~ ^[a-z0-9_][a-z0-9._+-]*$ ]]) || [[ $owner == */* || -z $repo ]]; then
  echo "Error: '$target' does not give a usable theme name / GitHub repo." >&2
  exit 1
fi

# Fetching and rebuilding print progress; from the menu there's no terminal,
# so re-run in Omarchy's floating one with the resolved target.
if [ ! -t 1 ]; then
  exec omarchy-launch-floating-terminal-with-presentation "omarchy-theme-install '$target'"
fi

echo ":: Fetching $owner/$repo ..."
if ! prefetch=$(nix flake prefetch --json "github:$owner/$repo"); then
  echo "Error: could not fetch github:$owner/$repo" >&2
  exit 1
fi
store=$(jq -r '.storePath' <<<"$prefetch")

# Same acceptance as Omarchy: a colors.toml, or an alacritty.toml to derive
# one from.
if [ ! -f "$store/colors.toml" ] && [ ! -f "$store/alacritty.toml" ]; then
  echo "Error: $owner/$repo has neither colors.toml nor alacritty.toml; not an Omarchy theme." >&2
  exit 1
fi

tmp=$(mktemp)
jq --arg n "$name" --arg o "$owner" --arg r "$repo" --argjson p "$prefetch" '
    .installed = ((.installed // {}) + { ($n): { owner: $o, repo: $r, rev: $p.locked.rev, narHash: $p.hash } })
    | .theme = $n' "$theme_json" >"$tmp"
mv "$tmp" "$theme_json"

echo ":: Installed '$name'; switching to it."
omarchy-nixos-rebuild
