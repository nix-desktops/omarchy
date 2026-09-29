# Omasusuwatari: soot sprites on the desktop. The bar widget toggles
# <plugin>/bin/susuwatari, a C layer-shell program it would `make` on first
# use. Pattern: a helper inside the plugin's tree.
{ lib, stdenv, fetchFromGitHub, pkg-config, wayland, cairo }:
let
  src = fetchFromGitHub {
    owner = "JoeJoeflyn";
    repo = "omasusuwatari";
    rev = "c50e496ea2cc7ad92c35c6da2eb507ef8b0885f7";
    hash = "sha256-514lhx4dnasVfFrVt/rBJgfVQda5L+EXCSZI6MsYwIM=";
  };
  susuwatari = stdenv.mkDerivation {
    pname = "susuwatari";
    version = "0-unstable-c50e496";
    inherit src;
    nativeBuildInputs = [ pkg-config ];
    buildInputs = [ wayland cairo ];
    installPhase = "install -Dm755 bin/susuwatari $out/bin/susuwatari";
    meta.mainProgram = "susuwatari";
  };
in
{
  inherit src;
  helpers."bin/susuwatari" = lib.getExe susuwatari;
  meta.description = "Desktop soot sprites (susuwatari built from src/)";
}
