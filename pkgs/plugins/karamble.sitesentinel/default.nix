# Site Sentinel: website uptime monitor. Service.qml runs
# <plugin>/bin/sentinel (Go: checks, alerts, an MCP server), which the
# Makefile builds once after install. Pattern: a helper inside the tree.
{ lib, fetchFromGitHub, buildGoModule, libnotify }:
let
  src = fetchFromGitHub {
    owner = "karamble";
    repo = "omarchy-site-sentinel";
    rev = "064981243c67f90c383c9752dc92d750d2454569";
    hash = "sha256-BRBIODcMUTweL3/1dBaE9x/iBQV66TnLMuHLlvgrAPI=";
  };
  sentinel = buildGoModule {
    pname = "sentinel";
    version = "0-unstable-0649812";
    inherit src;
    vendorHash = "sha256-NbuvbsmNbz3aKdjyyfpkbi52yRhXl473j3LvAUDn3L8=";
    subPackages = [ "cmd/sentinel" ];
    env.CGO_ENABLED = 0;
    meta.mainProgram = "sentinel";
  };
in
{
  inherit src;
  helpers."bin/sentinel" = lib.getExe sentinel;
  packages = [ libnotify ];
  meta.description = "Website uptime monitor (sentinel built from cmd/sentinel)";
}
