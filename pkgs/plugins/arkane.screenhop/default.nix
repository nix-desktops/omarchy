# ScreenHop: device previews of a website. Its default previews run node
# scripts with Chromium (Omarchy's); the opt-in native previews run
# .native/screenhop-native, a Qt WebEngine app that scripts/install.sh
# builds with /usr/lib/qt6/moc. Pattern: a helper inside the plugin's tree
# (a separate Qt process, so Nixpkgs 26.05's Qt).
{ lib, stdenv, fetchFromGitHub, pkg-config, qt6, libx11, libxext, nodejs }:
let
  src = fetchFromGitHub {
    owner = "jeremielumandong";
    repo = "omarchy-screenhop";
    rev = "dfc04c88219ebfae94b3943e1ed641cd01929bb8";
    hash = "sha256-JYhfmu0BkR9EK4dMy5HJAh/zBj8oVfXTSsiyZbHPzwI=";
  };

  screenhop-native = stdenv.mkDerivation {
    pname = "screenhop-native";
    version = "0-unstable-dfc04c8";
    inherit src;
    nativeBuildInputs = [ pkg-config qt6.wrapQtAppsHook ];
    buildInputs = [ qt6.qtbase qt6.qtdeclarative qt6.qtwebengine libx11 libxext ];
    # As scripts/build-native.sh does.
    buildPhase = ''
      mkdir -p .native
      ${qt6.qtbase}/libexec/moc native/main.cpp -o .native/main.moc
      $CXX -std=c++17 -O2 -fPIC -I.native native/main.cpp -o screenhop-native \
        $(pkg-config --cflags --libs Qt6WebEngineQuick Qt6Quick Qt6Network x11 xext)
    '';
    installPhase = "install -Dm755 screenhop-native $out/bin/screenhop-native";
    meta.mainProgram = "screenhop-native";
  };
in
{
  inherit src;
  helpers.".native/screenhop-native" = lib.getExe screenhop-native;
  packages = [ nodejs ];
  meta.description = "Website device previews (node; the native previewer built with Qt WebEngine)";
}
