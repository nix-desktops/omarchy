# IDÅSEN Desk: Panel.qml talks to `idasen controller` (Go, Bluetooth LE over
# BlueZ's D-Bus) at the binaryPath setting, default ~/.local/bin/idasen.
# Pattern: a link in the home.
{ lib, fetchFromGitHub, buildGoModule }:
let
  src = fetchFromGitHub {
    owner = "edofic";
    repo = "go-idasen";
    rev = "d67ca4de3fb27c87e4025168ff149975489bb6f1";
    hash = "sha256-SCOjoTY1PLTD7Dc75V+j6bSYHSnBkAJgOnHIGSJ8EaY=";
  };

  idasen = buildGoModule {
    pname = "go-idasen";
    version = "0.2.4-unstable-d67ca4d";
    inherit src;
    vendorHash = "sha256-dx5NNBZXJSCODM5LZMPpnAflPkJeEb5QIZZOppRRGbM=";
    subPackages = [ "." ];
    postInstall = "mv $out/bin/go-idasen $out/bin/idasen";
    meta.mainProgram = "idasen";
  };
in
{
  inherit src;
  home.".local/bin/idasen" = lib.getExe idasen;
  meta.description = "IKEA IDÅSEN desk controls (idasen built from the repo, linked at ~/.local/bin)";
}
