# Desktop Undo: reopens closed windows. Service.qml runs <plugin>/bin/undo-probe
# (Rust, src/undo-probe: a closed window's process tree) and falls back to
# compat/undo-probe.sh without it. Pattern: a helper inside the plugin's tree.
{ lib, fetchFromGitHub, rustPlatform }:
let
  src = fetchFromGitHub {
    owner = "ccdwyer";
    repo = "omarchy-desktop-undo";
    rev = "b4f1ca212744ea17aa00ebfdb66293ccd8c60893";
    hash = "sha256-1B9+cwaqcQJFXNfXPEv6/dgoMtbN6xNIzAv37wAT4HE=";
  };

  undo-probe = rustPlatform.buildRustPackage {
    pname = "undo-probe";
    version = "1.0.0-unstable-b4f1ca2";
    inherit src;
    sourceRoot = "${src.name}/src/undo-probe";
    cargoHash = "sha256-tvICx6BmP1L/DXghrO0eo5CgOm3Q5Baf+6s38kx2vTE=";
    meta.mainProgram = "undo-probe";
  };
in
{
  inherit src;
  helpers."bin/undo-probe" = lib.getExe undo-probe;
  meta.description = "Undo closed windows (undo-probe built from src/undo-probe)";
}
