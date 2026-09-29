# omaportless: .localhost names for local dev servers. Service.qml runs
# <plugin>/omaportless, which upstream's `setup` builds with cargo. Its
# optional port-80 redirect writes /etc (root) and doesn't apply on NixOS;
# the proxy itself runs as a user unit it writes pointing at the binary.
# Pattern: a helper inside the plugin's tree.
{ lib, fetchFromGitHub, rustPlatform }:
let
  src = fetchFromGitHub {
    owner = "dingyi";
    repo = "omaportless";
    rev = "894ebae20f812d2dbc99174aa75d724ca4821c64";
    hash = "sha256-yqixizwzkrM2uVW4idY09n+gSf3ewVjz3JutSBOl2zE=";
  };

  omaportless = rustPlatform.buildRustPackage {
    pname = "omaportless";
    version = "0-unstable-894ebae";
    inherit src;
    cargoHash = "sha256-dej8BKruZW8gNf7eHbv0n4kptSzzwQYQLe7wOI1eKqI=";
    meta.mainProgram = "omaportless";
  };
in
{
  inherit src;
  helpers."omaportless" = lib.getExe omaportless;
  meta.description = "Local dev server names (omaportless built from the repo)";
}
