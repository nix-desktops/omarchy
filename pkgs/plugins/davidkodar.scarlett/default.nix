# Scarlett: Focusrite Scarlett mixer controls. Panel.qml runs
# <plugin>/bin/scarlett-helper (ALSA controls as JSON), which upstream's
# install.sh builds with make. Pattern: a helper inside the plugin's tree.
{ lib, stdenv, fetchFromGitHub, pkg-config, alsa-lib, json_c }:
let
  src = fetchFromGitHub {
    owner = "davidkodar";
    repo = "omarchy-scarlett";
    rev = "3774fc415fb5cccf89d27ed73f2caee507a3bb4e";
    hash = "sha256-Y+cqzk9F0fjKr9Hc86/CZzsFMMIYjjqDTWGoKr2n4M0=";
  };
  scarlett-helper = stdenv.mkDerivation {
    pname = "scarlett-helper";
    version = "0-unstable-3774fc4";
    inherit src;
    nativeBuildInputs = [ pkg-config ];
    buildInputs = [ alsa-lib json_c ];
    installPhase = "install -Dm755 bin/scarlett-helper $out/bin/scarlett-helper";
    meta.mainProgram = "scarlett-helper";
  };
in
{
  inherit src;
  helpers."bin/scarlett-helper" = lib.getExe scarlett-helper;
  meta.description = "Focusrite Scarlett controls (scarlett-helper built from src/)";
}
