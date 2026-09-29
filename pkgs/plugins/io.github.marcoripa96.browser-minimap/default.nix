# Browser minimap: agent-browser's sessions as a live minimap. bridge.sh
# runs bridge/target/release/omarchy-browser-minimap-bridge when present,
# else downloads a release binary. Pattern: a helper at the dev-build path.
{ lib, fetchFromGitHub, rustPlatform, agent-browser }:
let
  src = fetchFromGitHub {
    owner = "marcoripa96";
    repo = "omarchy-browser-minimap";
    rev = "e372fac654a0e7b569982258ac9d0ab5221fcd27";
    hash = "sha256-36SQqDxL5whjbYxIxucJ/m9XrElKB7MtySmbERp0rHQ=";
  };
  bridge = rustPlatform.buildRustPackage {
    pname = "omarchy-browser-minimap-bridge";
    version = "1.1.1-unstable-e372fac";
    inherit src;
    sourceRoot = "${src.name}/bridge";
    cargoHash = "sha256-GQGrldC+hhK/wS/dbEadl2sNEbGzWeUJYSjkHd8W7cM=";
    meta.mainProgram = "omarchy-browser-minimap-bridge";
  };
in
{
  inherit src;
  helpers."bridge/target/release/omarchy-browser-minimap-bridge" = lib.getExe bridge;
  packages = [ agent-browser ];
  meta.description = "agent-browser minimap (its bridge built from bridge/)";
}
