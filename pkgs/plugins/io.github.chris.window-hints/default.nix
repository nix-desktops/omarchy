# Window Hints: keyboard hints for windows. Service.qml runs
# <plugin>/bin/hints-ctl (Rust, src/hints-ctl) and falls back to
# compat/hints-ctl.sh without it. Pattern: a helper inside the plugin's tree.
{ lib, fetchFromGitHub, rustPlatform }:
let
  src = fetchFromGitHub {
    owner = "ccdwyer";
    repo = "omarchy-window-hints";
    rev = "52a9cf583c5051fef5ca7c8e1f62f5ac55bdd4d0";
    hash = "sha256-fuj05Nu68gjXbZR1mYDVpJ8mTDmRt6XCzmdyRPvGtV0=";
  };

  hints-ctl = rustPlatform.buildRustPackage {
    pname = "hints-ctl";
    version = "1.0.0-unstable-52a9cf5";
    inherit src;
    sourceRoot = "${src.name}/src/hints-ctl";
    cargoHash = "sha256-0GJlmrhfcSUqsUBQKJL4vIFkw2dhXDR6V2B8RwWD5W8=";
    meta.mainProgram = "hints-ctl";
  };
in
{
  inherit src;
  helpers."bin/hints-ctl" = lib.getExe hints-ctl;
  meta.description = "Window hints (hints-ctl built from src/hints-ctl)";
}
