# `autoSave`: every fresh capture is also saved to the screenshot directory
# (OMASNAP_SCREENSHOT_DIR, else [output] directory, else ~/Pictures/Screenshots),
# not only copied and previewed. Upstream saves only from the editor or with
# --save; omasnap-autosave.patch adds the switch (OMASNAP_AUTOSAVE, or
# `autosave = true` under [output] in ~/.config/omasnap/omasnap.conf), and
# this sets the environment default, which both still override.
{ lib, stdenv, inputs, cmake, ninja, pkg-config, qt6, kdePackages, wayland
, wayland-scanner, wayland-protocols, tesseract, wl-clipboard
, autoSave ? false }:

stdenv.mkDerivation {
  pname = "omasnap";
  version = "1.21.0";
  src = inputs.omasnap;

  patches = [ ./omasnap-autosave.patch ];

  nativeBuildInputs = [ cmake ninja pkg-config wayland-scanner qt6.wrapQtAppsHook ];

  # The protocol XMLs, from /usr/share upstream.
  postPatch = ''
    substituteInPlace CMakeLists.txt \
      --replace-fail /usr/share/wayland-protocols ${wayland-protocols}/share/wayland-protocols
  '';
  buildInputs = [ qt6.qtbase qt6.qtwayland kdePackages.layer-shell-qt wayland ];

  # OCR and the clipboard, called by name.
  qtWrapperArgs = [ "--prefix" "PATH" ":" (lib.makeBinPath [ tesseract wl-clipboard ]) ]
    ++ lib.optionals autoSave [ "--set-default" "OMASNAP_AUTOSAVE" "1" ];

  meta = {
    description = "Native Wayland screenshot and annotation editor for Omarchy and Hyprland";
    homepage = "https://github.com/omacom/omasnap";
    license = with lib.licenses; [ mit ofl ];
    mainProgram = "omasnap";
    platforms = lib.platforms.linux;
  };
}
