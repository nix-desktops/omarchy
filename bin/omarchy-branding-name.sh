# Set the name the boot splash, login screen, screensaver and About screen
# show (Style > Branding). Upstream swaps the Plymouth and SDDM logos in
# /usr/share; here the name goes into the host's branding.json
# (omarchy.stateDir), a wordmark in Omarchy's style is drawn from it, and the
# system rebuilds.
#
#   omarchy-branding-name            ask for the name
#   omarchy-branding-name <name>     set it
#   omarchy-branding-name reset      back to Omarchy
state="$OMARCHY_STATE/branding.json"

current=Omarchy
[[ -f $state ]] && current=$(jq -r '.name // "Omarchy"' "$state")

name="${1:-}"
if [[ -z $name ]]; then
  name=$(gum input --header "Name on the boot splash, login screen and screensaver" \
    --placeholder "Omarchy" --value "$current") || exit 0
fi
[[ $name == reset ]] && name=Omarchy
name=$(printf '%s' "$name" | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//')
if [[ -z $name ]]; then
  echo "No name given." >&2
  exit 1
fi
if [[ $name == "$current" ]]; then
  echo "Already $name."
  exit 0
fi

if [[ ! -f $state ]]; then
  echo '{}' >"$state"
  # Flakes only see tracked files.
  git -C "$(dirname "$state")" add --intent-to-add "$(basename "$state")" 2>/dev/null || true
fi
tmp=$(mktemp)
jq --arg n "$name" '.name = $n' "$state" >"$tmp"
mv "$tmp" "$state"

echo "Branding as $name..."
omarchy-nixos-rebuild
