# omaloop: a loop synthesizer panel. OmaloopPanel.qml runs the Rust engine
# (engine/, cpal over ALSA) at <plugin>/engine/target/release/omaloop-engine,
# where install.sh's cargo build leaves it. Pattern: a helper inside the
# plugin's tree.
{ lib, fetchFromGitHub, rustPlatform, pkg-config, alsa-lib }:
let
  src = fetchFromGitHub {
    owner = "joshuaswarren";
    repo = "omaloop";
    rev = "fc5b3f9ce0dd10585df018ab12aaf31298e9b3d2";
    hash = "sha256-2v3Ev54+YQqWdiO0O0CHXTiA/duA6uLC4EZhwx6xveM=";
  };

  engine = rustPlatform.buildRustPackage {
    pname = "omaloop-engine";
    version = "0.1.0-unstable-fc5b3f9";
    inherit src;
    sourceRoot = "${src.name}/engine";
    cargoHash = "sha256-JM/1BkgdwwkorEejXUL4f871iFTS8Bxg9h+dsUuEO1E=";
    nativeBuildInputs = [ pkg-config ];
    buildInputs = [ alsa-lib ];
    meta.mainProgram = "omaloop-engine";
  };
in
{
  inherit src;
  helpers."engine/target/release/omaloop-engine" = lib.getExe engine;
  meta.description = "Loop synthesizer (omaloop-engine built from engine/)";
}
