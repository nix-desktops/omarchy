# Share Cloak: hides windows while screen sharing. Service.qml runs
# <plugin>/bin/cloak-probe (pw-dump parsing), built by build.sh with cargo,
# else a shell fallback. Pattern: a helper inside the plugin's tree.
{ lib, fetchFromGitHub, rustPlatform, pipewire, mako }:
let
  src = fetchFromGitHub {
    owner = "ccdwyer";
    repo = "omarchy-share-cloak";
    rev = "2ce67e29620dff5be1f8b6c8777f75945a94da79";
    hash = "sha256-Ltz9u/LbxIlfj2Gtj9X197KAn2QPrhnwAukQaKy29Mk=";
  };
  cloak-probe = rustPlatform.buildRustPackage {
    pname = "cloak-probe";
    version = "0-unstable-2ce67e2";
    inherit src;
    sourceRoot = "${src.name}/src/cloak-probe";
    cargoHash = "sha256-ujDewD6jtYG4/5pKbFawSHDyuP7ZCnYv37umbI5OFBs=";
    meta.mainProgram = "cloak-probe";
  };
in
{
  inherit src;
  helpers."bin/cloak-probe" = lib.getExe cloak-probe;
  # pw-dump, makoctl (do-not-disturb while sharing).
  packages = [ pipewire mako ];
  meta.description = "Hide windows while screen sharing (cloak-probe built from src/cloak-probe)";
}
