{ lib, stdenv, inputs, cmake, ninja, pkg-config, qt6, kdePackages, wayland
, wayland-scanner, wayland-protocols, tesseract, wl-clipboard }:

stdenv.mkDerivation {
  pname = "omasnap";
  version = "1.21.0";
  src = inputs.omasnap;

  nativeBuildInputs = [ cmake ninja pkg-config wayland-scanner qt6.wrapQtAppsHook ];

  # The protocol XMLs, from /usr/share upstream.
  postPatch = ''
    substituteInPlace CMakeLists.txt \
      --replace-fail /usr/share/wayland-protocols ${wayland-protocols}/share/wayland-protocols
  '';
  buildInputs = [ qt6.qtbase qt6.qtwayland kdePackages.layer-shell-qt wayland ];

  # OCR and the clipboard, called by name.
  qtWrapperArgs = [ "--prefix" "PATH" ":" (lib.makeBinPath [ tesseract wl-clipboard ]) ];

  meta = {
    description = "Native Wayland screenshot and annotation editor for Omarchy and Hyprland";
    homepage = "https://github.com/omacom/omasnap";
    license = with lib.licenses; [ mit ofl ];
    mainProgram = "omasnap";
    platforms = lib.platforms.linux;
  };
}
