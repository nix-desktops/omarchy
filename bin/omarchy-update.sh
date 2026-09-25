# Update / maintenance (the NixOS analog of omarchy-update). Without an
# argument this is what Update > Omarchy does upstream: update everything —
# here, bump the flake inputs (nixpkgs, home-manager, Omarchy itself, …) and
# rebuild.
case "${1-inputs}" in
system)
  # Apply the current state of the config repo.
  omarchy-nixos-rebuild
  ;;
inputs)
  cd "$OMARCHY_CONFIG" || exit 1
  if [ "$(uname -m)" != "x86_64" ]; then
    echo "⚠  Asahi host: bumping nixpkgs-25-11 can miss the Asahi binary cache"
    echo "   and force a ~30-60 min local kernel/Mesa rebuild."
    gum confirm "Bump flake inputs anyway?" || exit 0
  fi
  nix flake update
  git -C "$OMARCHY_CONFIG" diff --stat flake.lock 2>/dev/null || true
  omarchy-nixos-rebuild
  ;;
rollback)
  echo ":: System generations:"
  sudo nix-env -p /nix/var/nix/profiles/system --list-generations | tail -n 10
  echo
  gum confirm "Roll back to the previous generation?" || exit 0
  sudo nixos-rebuild switch --rollback
  ;;
clean)
  echo ":: Deleting generations older than 14 days and collecting garbage..."
  sudo nix-collect-garbage --delete-older-than 14d
  nix-collect-garbage --delete-older-than 14d
  echo ":: Done."
  ;;
*)
  echo "Usage: omarchy-update [system|inputs|rollback|clean]" >&2
  exit 1
  ;;
esac
