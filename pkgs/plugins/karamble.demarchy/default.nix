# Demarchy: Decred staking, node and Bison Relay messages, all from the Go
# helper Panel.qml runs as <plugin>/bin/demarchy (the Makefile's go build).
# Pattern: a helper inside the plugin's tree.
{ lib, fetchFromGitHub, buildGoModule }:
let
  src = fetchFromGitHub {
    owner = "karamble";
    repo = "demarchy";
    rev = "848ee4485e6eea5e4597e4ee36b0b91c412b308f";
    hash = "sha256-iJpePhZs9Q/uNrih2vuz59h+SrersZJcX9kaiN/lCnk=";
  };

  demarchy = buildGoModule {
    pname = "demarchy";
    version = "0-unstable-848ee44";
    inherit src;
    vendorHash = null; # standard library only
    subPackages = [ "cmd/demarchy" ];
    meta.mainProgram = "demarchy";
  };
in
{
  inherit src;
  helpers."bin/demarchy" = lib.getExe demarchy;
  meta.description = "Decred dashboard (demarchy built from cmd/demarchy)";
}
