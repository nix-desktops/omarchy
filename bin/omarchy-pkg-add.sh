# Upstream's non-interactive install; here it's omarchy-pkg-install with the
# names mapped to nixpkgs attributes.
mapfile -t attrs < <(omarchy-pkg-attr "$@")
exec omarchy-pkg-install "${attrs[@]}"
