# Pitwall: live terminal sessions and AI agents in the bar. Widget.qml runs
# $HOME/.local/bin/pitwall (snapshot, resume, chat), which upstream's
# install.sh builds with cargo. Pattern: a link in the home.
{ lib, fetchFromGitHub, rustPlatform, git }:
let
  src = fetchFromGitHub {
    owner = "omgxai";
    repo = "pitwall";
    rev = "a54ae55a48f29829b8b1abe9c3a417bea69fd732";
    hash = "sha256-i58pA9JJY1wCT5b7CnU9kCuvCeHuVpXjR3xZmp++1co=";
  };

  pitwall = rustPlatform.buildRustPackage {
    pname = "pitwall";
    version = "0.1.0-unstable-a54ae55";
    inherit src;
    cargoHash = "sha256-OQEPSibGZU4a6yC5/ofREGxxUn0tYiH2VAV9aDX3fVA=";
    nativeCheckInputs = [ git ];
    meta.mainProgram = "pitwall";
  };
in
{
  inherit src;
  home.".local/bin/pitwall" = lib.getExe pitwall;
  meta.description = "Sessions and agents in the bar (pitwall built from the repo, linked at ~/.local/bin)";
}
