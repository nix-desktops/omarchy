# A wordmark for another name, in the style of Omarchy's: logo.txt (the
# ASCII art the screensaver and About screen show) in the figlet font
# Omarchy's is drawn in, and logo.png (the boot splash and login screen)
# rendered from that same art in Omarchy's green, at its proportions.
{
  lib,
  runCommand,
  fetchurl,
  figlet,
  imagemagick,
  dejavu_fonts,
  name,
}:
let
  font = fetchurl {
    name = "delta-corps-priest-1.flf";
    url = "https://raw.githubusercontent.com/xero/figlet-fonts/417429ef36ab039cbf192a4424c60aa23fc32de8/Delta%20Corps%20Priest%201.flf";
    hash = "sha256-UGXwCqYVxeL6GOn3hxYoywOE6dkVTRUxCW463A2E1B8=";
  };
in
runCommand "omarchy-branding-${lib.strings.sanitizeDerivationName (lib.toLower name)}"
  {
    nativeBuildInputs = [ figlet imagemagick ];
    text = lib.toLower name;
  }
  ''
    mkdir -p $out fonts
    cp ${font} fonts/brand.flf
    figlet -d fonts -f brand -w 1000 "$text" | sed 's/[[:space:]]*$//' > $out/logo.txt
    # Block characters from a monospace font tile into pixels; Omarchy's
    # wordmark is 800 wide and a sixth taller than the art renders.
    magick -background none -fill '#A8CD76' \
      -font ${dejavu_fonts}/share/fonts/truetype/DejaVuSansMono.ttf -pointsize 48 \
      label:@$out/logo.txt -trim +repage -resize 800x -resize '100%x117%' \
      -depth 8 $out/logo.png
  ''
