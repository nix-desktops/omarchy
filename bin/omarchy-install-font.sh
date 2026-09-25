# Install a Nerd Font and switch to it (omarchy-install-font, NixOS
# edition). Upstream passes the Arch package; map it to the nixpkgs one,
# install declaratively, then let omarchy-font-set switch fontconfig.
#   omarchy-install-font <display-name> <arch-package> <family>
[ $# -eq 3 ] || { echo "Usage: omarchy-install-font <display-name> <package> <family>" >&2; exit 1; }
family="$3"
case "$2" in
  ttf-cascadia-mono-nerd) attr=nerd-fonts.caskaydia-mono ;;
  ttf-meslo-nerd) attr=nerd-fonts.meslo-lg ;;
  ttf-firacode-nerd) attr=nerd-fonts.fira-code ;;
  ttf-victor-mono-nerd) attr=nerd-fonts.victor-mono ;;
  ttf-bitstream-vera-mono-nerd) attr=nerd-fonts.bitstream-vera-sans-mono ;;
  ttf-iosevka-nerd) attr=nerd-fonts.iosevka ;;
  ttf-jetbrains-mono-nerd*) attr=nerd-fonts.jetbrains-mono ;;
  *) echo "No nixpkgs mapping for '$2'; install it with Install > Package." >&2; exit 1 ;;
esac

if [ ! -t 1 ]; then
  exec omarchy-launch-floating-terminal-with-presentation "omarchy-install-font '$1' '$2' '$family'"
fi
omarchy-pkg-install "$attr" && fc-cache -f && omarchy-font-set "$family"
