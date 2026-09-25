# Apply the theme color to Chromium-family browsers (omarchy-theme-set-
# browser, NixOS edition). The color is a browser policy the omarchy NixOS
# module writes on rebuild; this only makes running browsers pick it up.
for browser in chromium google-chrome-stable brave microsoft-edge-stable; do
  if command -v "$browser" >/dev/null && pgrep -f "$browser" >/dev/null; then
    "$browser" --refresh-platform-policy --no-startup-window >/dev/null 2>&1 &
  fi
done
exit 0
