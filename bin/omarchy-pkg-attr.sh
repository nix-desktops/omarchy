# The nixpkgs attribute for a package name as upstream's commands pass it
# (Arch/AUR names: omarchy-pkg-add visual-studio-code-bin, …), from the
# flake's Arch→nixpkgs map (data/arch-packages.json, which the pacman shim
# and the plugin doctor use too) and its rules: python-foo →
# python3Packages.foo, qt6-foo → kdePackages.qtfoo, qt5-foo →
# libsForQt5.qtfoo, a -bin/-git/-appimage suffix dropped. Names that are
# already nixpkgs attributes, or have no nixpkgs counterpart, pass through
# unchanged (an unknown attribute is skipped at build time, with a warning).
attr_of() {
  local name=$1 attr
  attr=$(jq -r --arg n "$name" '.map[$n] // empty' "$OMARCHY_ARCH_PACKAGES" 2>/dev/null || true)
  if [[ -n $attr ]]; then
    echo "$attr"
    return
  fi
  if jq -e --arg n "$name" '.map | has($n)' "$OMARCHY_ARCH_PACKAGES" >/dev/null 2>&1; then
    echo "$name" # mapped to null: no nixpkgs counterpart
    return
  fi
  case "$name" in
  python-*) echo "python3Packages.${name#python-}" ;;
  qt6-*) echo "kdePackages.qt${name#qt6-}" ;;
  qt5-*) echo "libsForQt5.qt${name#qt5-}" ;;
  *-bin | *-git | *-appimage) attr_of "${name%-*}" ;;
  *) echo "$name" ;;
  esac
}
for name in "$@"; do
  attr_of "$name"
done
