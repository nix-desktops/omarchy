# Omagihu: GitHub dashboard. Service.qml runs <plugin>/bin/omagihud and the
# panel <plugin>/bin/omagihu; bin/ isn't committed (`make` builds it).
# Pattern: helpers inside the plugin's tree.
{ lib, fetchFromGitHub, buildGoModule }:
let
  src = fetchFromGitHub {
    owner = "karamble";
    repo = "omarchy-omagihu";
    rev = "86cb1d78c590535863b54ef80f73e3a606e15824";
    hash = "sha256-18M3C6HSNJt2e6lQeVg2ACRDDZhqZEgZWK74cVXXOA8=";
  };

  omagihu = buildGoModule {
    pname = "omagihu";
    version = "0.3.0-unstable-86cb1d7";
    inherit src;
    vendorHash = "sha256-T4Xw573z0pgfO1Ce6awZSr4RA7VLyrJJGY6NPLp/vrI=";
    subPackages = [ "cmd/omagihu" "cmd/omagihud" "cmd/omagihu-setup" ];
    env.CGO_ENABLED = 0;
    ldflags = [ "-X main.version=0.3.0" ];
  };
in
{
  inherit src;
  helpers = {
    "bin/omagihu" = "${omagihu}/bin/omagihu";
    "bin/omagihud" = "${omagihu}/bin/omagihud";
    "bin/omagihu-setup" = "${omagihu}/bin/omagihu-setup";
  };
  meta.description = "GitHub activity dashboard (omagihu, omagihud built from cmd/)";
}
