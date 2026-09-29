# Pipelines: GitHub Actions status. Service.qml runs
# <plugin>/bin/omarchy-pipelines-helper (Rust, backend/: polls the API),
# which build.sh compiles and install.sh downloads. Pattern: a helper inside
# the plugin's tree.
{ lib, fetchFromGitHub, rustPlatform }:
let
  src = fetchFromGitHub {
    owner = "alexandre-vl";
    repo = "omarchy-pipelines";
    rev = "7ff311ca8e59b71f32d67117dee3ea5017f992cb";
    hash = "sha256-ivKaKUoYsojHU9kcb30QFC2YsIRqHTgYwMHRmd0qtAg=";
  };

  helper = rustPlatform.buildRustPackage {
    pname = "omarchy-pipelines-helper";
    version = "0.1.0-unstable-7ff311c";
    inherit src;
    sourceRoot = "${src.name}/backend";
    cargoHash = "sha256-Y/HtW7VezXZ6I+URvYRxkZVek8e8eqifVYRJJKm3U5Q=";
    meta.mainProgram = "omarchy-pipelines-helper";
  };
in
{
  inherit src;
  helpers."bin/omarchy-pipelines-helper" = lib.getExe helper;
  meta.description = "GitHub Actions pipelines (omarchy-pipelines-helper built from backend/)";
}
