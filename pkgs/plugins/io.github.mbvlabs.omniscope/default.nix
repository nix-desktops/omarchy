# OmniScope: a launcher whose file search runs <plugin>/bin/omniscope-search,
# a Rust worker shipped prebuilt (glibc-dynamic: it'd need nix-ld). Built
# from the repo's own crate instead. Pattern: a helper inside the plugin's
# tree, replacing a shipped binary.
{ lib, fetchFromGitHub, rustPlatform }:
let
  src = fetchFromGitHub {
    owner = "mbvlabs";
    repo = "omniscope";
    rev = "b4ef69affa57bacc36a0bcd6f789abe5d686af78";
    hash = "sha256-xJwvWJB9X6bBK2CTRqAosrGCrGjeYZgYlMLYeuj/OAM=";
  };

  omniscope-search = rustPlatform.buildRustPackage {
    pname = "omniscope-search";
    version = "0.1.0-unstable-b4ef69a";
    inherit src;
    cargoHash = "sha256-OQjgm+2K0ZqeeMK1CB0H9Bhr02ZqQ2Sa30n9bl3bZGc=";
    meta.mainProgram = "omniscope-search";
  };
in
{
  inherit src;
  helpers."bin/omniscope-search" = lib.getExe omniscope-search;
  meta.description = "Launcher with file search (omniscope-search built from source)";
}
