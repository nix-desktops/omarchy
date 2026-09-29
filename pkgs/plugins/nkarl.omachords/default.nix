# Omachords: a chord pad. EngineAdapter.qml runs
# <plugin>/engine/target/release/omachords-engine (Rust, cpal on ALSA) and
# feeds it JSON lines. Pattern: a helper at the cargo target path.
{ lib, fetchFromGitHub, rustPlatform, pkg-config, alsa-lib }:
let
  src = fetchFromGitHub {
    owner = "nkarl";
    repo = "omachords";
    rev = "d786bd760e1c6fa92217f71cd91e9576ed7bd9f1";
    hash = "sha256-XCB18eFN0gFiPFD3GH6OZNEWiU2x5+6LycyhQQ0/nCQ=";
  };
  engine = rustPlatform.buildRustPackage {
    pname = "omachords-engine";
    version = "0-unstable-d786bd7";
    inherit src;
    sourceRoot = "${src.name}/engine";
    cargoHash = "sha256-2So5NSWUvQpXjSGF0KErJyc9a6/zEpUsV3OI0DgTzvA=";
    nativeBuildInputs = [ pkg-config ];
    buildInputs = [ alsa-lib ];
    meta.mainProgram = "omachords-engine";
  };
in
{
  inherit src;
  helpers."engine/target/release/omachords-engine" = lib.getExe engine;
  meta.description = "Chord pad (omachords-engine built from engine/)";
}
