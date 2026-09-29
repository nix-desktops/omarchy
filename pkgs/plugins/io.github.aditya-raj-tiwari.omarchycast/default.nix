# Omarchycast: a launcher overlay whose search, calculator and app index
# come from the omarchycastd daemon (Rust, daemon/), started as
# `omarchycastd` from PATH (upstream's Makefile installs it to
# ~/.local/bin). Pattern: a helper on PATH.
{ lib, fetchFromGitHub, rustPlatform }:
let
  src = fetchFromGitHub {
    owner = "Aditya-Raj-Tiwari";
    repo = "omarchycast";
    rev = "98348ff936ebb8c13e5b899cc82f57caeeb14592";
    hash = "sha256-AoAAqgenHZ7vdGNQzxBjGkB82kZ9zeY/G9/Wb8Br7wo=";
  };

  omarchycastd = rustPlatform.buildRustPackage {
    pname = "omarchycastd";
    version = "0.2.2-unstable-98348ff";
    inherit src;
    sourceRoot = "${src.name}/daemon";
    cargoHash = "sha256-7JKqDcB0qsHONLJ7uGOeFiNOs74tSPtglxmEjDzcW4A=";
    meta.mainProgram = "omarchycastd";
  };
in
{
  inherit src;
  # The optional notes viewer (notesapp/, PyGObject + WebKit) isn't included.
  packages = [ omarchycastd ];
  meta.description = "Launcher overlay (omarchycastd built from daemon/, on PATH)";
}
