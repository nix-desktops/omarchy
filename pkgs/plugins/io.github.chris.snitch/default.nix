# Snitch: connection monitor. Service.qml looks for <plugin>/bin/snitchd
# (upstream builds the workspace with cargo). Blocking goes through a root
# helper at /usr/lib/snitch/snitch-block with a polkit policy, which needs
# a NixOS module and isn't provided here. Pattern: a helper in the tree.
{ lib, fetchFromGitHub, rustPlatform }:
let
  src = fetchFromGitHub {
    owner = "ccdwyer";
    repo = "omarchy-snitch";
    rev = "147efa608ba56df3e8bcea0321e2c20d90b204dd";
    hash = "sha256-2XNaBcAcb/svUf2KODSSMXBqJeDzPBCu2zWJttPJaRc=";
  };

  snitchd = rustPlatform.buildRustPackage {
    pname = "snitchd";
    version = "1.0.0-unstable-147efa6";
    inherit src;
    cargoHash = "sha256-2xUHNw33yQy1dTQv9R1RPV3tuTiOrBKxIbHhgFhnYKc=";
    cargoBuildFlags = [ "-p" "snitchd" ];
    cargoTestFlags = [ "-p" "snitchd" ];
    meta.mainProgram = "snitchd";
  };
in
{
  inherit src;
  helpers."bin/snitchd" = lib.getExe snitchd;
  meta.description = "Network connection monitor (snitchd built from daemon/; no blocking helper)";
}
