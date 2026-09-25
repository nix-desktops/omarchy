# Install a browser (omarchy-install-browser, NixOS edition): add it to the
# host's apps.json and rebuild. Upstream also writes the browser policy and
# flags; here the theme color policy comes from the omarchy NixOS module
# (programs.chromium) for every Chromium-family browser.
#
#   omarchy-install-browser <chromium|chrome|brave|edge|firefox>
case "${1-}" in
chromium) attr=chromium; name=Chromium ;;
chrome) attr=google-chrome; name=Chrome ;;
brave) attr=brave; name=Brave ;;
edge) attr=microsoft-edge; name=Edge ;;
firefox) attr=firefox; name=Firefox ;;
brave-origin | zen)
  echo "$1 isn't packaged in nixpkgs." >&2
  exit 1
  ;;
*)
  echo "Usage: omarchy-install-browser <chromium|chrome|brave|edge|firefox>" >&2
  exit 1
  ;;
esac

echo "Installing $name..."
omarchy-pkg-install "$attr" || exit 1
echo ""
echo "$name browser installed. Make it the default via Setup > Defaults > Browser."
