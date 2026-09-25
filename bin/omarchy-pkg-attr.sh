# The nixpkgs attribute for a package name as upstream's commands pass it
# (Arch/AUR names: omarchy-pkg-add visual-studio-code-bin, …). Names that
# are already nixpkgs attributes, or have no nixpkgs counterpart, pass
# through unchanged (an unknown attribute is skipped at build time, with a
# warning).
for name in "$@"; do
  case "$name" in
  1password) echo _1password-gui ;;
  1password-cli) echo _1password-cli ;;
  brave-bin) echo brave ;;
  cursor-bin) echo code-cursor ;;
  google-chrome) echo google-chrome ;;
  heroic-games-launcher-bin) echo heroic ;;
  libappindicator-gtk3) echo libappindicator-gtk3 ;;
  microsoft-edge-stable-bin) echo microsoft-edge ;;
  omarchy-emacs) echo emacs-pgtk ;;
  zen-browser-bin) echo zen-browser ;;
  openbsd-netcat) echo netcat-openbsd ;;
  pam-u2f) echo pam_u2f ;;
  python-gpgme) echo python3Packages.gpgme ;;
  python-protobuf) echo python3Packages.protobuf ;;
  sublime-text-4) echo sublime4 ;;
  visual-studio-code-bin) echo vscode ;;
  wine-staging) echo wineWow64Packages.staging ;;
  zed) echo zed-editor ;;
  *) echo "$name" ;;
  esac
done
