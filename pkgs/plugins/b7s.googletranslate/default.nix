# Google Translate panel: Panel.qml runs <plugin>/bin/omarchy-googletranslate-request,
# a small libcurl C program the repo ships prebuilt (for Arch's /lib64
# loader). Pattern: the helper rebuilt from src/translate.c, in the tree.
{ lib, stdenv, fetchFromGitHub, pkg-config, curl }:
let
  src = fetchFromGitHub {
    owner = "b7s";
    repo = "omarchy-googletranslate";
    rev = "093a5c51c02718bc424b6197f027bae47458e6f1";
    hash = "sha256-CLM2DFIPPvYatWSeuBwHvybFxzON/LJjYH1M65DgynA=";
  };
  request = stdenv.mkDerivation {
    pname = "omarchy-googletranslate-request";
    version = "0-unstable-093a5c5";
    inherit src;
    nativeBuildInputs = [ pkg-config ];
    buildInputs = [ curl ];
    preBuild = "rm -f bin/omarchy-googletranslate-request";
    installPhase = "install -Dm755 bin/omarchy-googletranslate-request $out/bin/omarchy-googletranslate-request";
    meta.mainProgram = "omarchy-googletranslate-request";
  };
in
{
  inherit src;
  helpers."bin/omarchy-googletranslate-request" = lib.getExe request;
  meta.description = "Google Translate panel (its libcurl request helper built from src/)";
}
