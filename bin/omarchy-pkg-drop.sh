# Upstream's non-interactive removal; here it's omarchy-pkg-remove with the
# names mapped to nixpkgs attributes.
mapfile -t attrs < <(omarchy-pkg-attr "$@")
exec omarchy-pkg-remove "${attrs[@]}"
