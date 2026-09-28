# Secret Canary: Service.qml runs <plugin>/bin/canaryd (build.sh builds it
# with cargo) and falls back to a polling shell script without it.
# Pattern: a helper inside the plugin's tree.
{ lib, fetchFromGitHub, rustPlatform }:
let
  src = fetchFromGitHub {
    owner = "ccdwyer";
    repo = "omarchy-secret-canary";
    rev = "33042bed1cc4ed03f3f5c384e135a7ac9b9d356d";
    hash = "sha256-0I5CG26v7Y+C6mzZKf/NoG0L+hh/ExckAxdBfRxQbZ4=";
  };

  canaryd = rustPlatform.buildRustPackage {
    pname = "canaryd";
    version = "1.0.0-unstable-33042be";
    inherit src;
    sourceRoot = "${src.name}/src/canaryd";
    cargoHash = "sha256-cLdpePZTr2/APjR34onHXIlkxZqya4ve5+8xJXIlOus=";
    meta.mainProgram = "canaryd";
  };
in
{
  inherit src;
  helpers."bin/canaryd" = lib.getExe canaryd;
  meta.description = "Clipboard and staged-diff secret watcher (canaryd built from src/canaryd)";
}
