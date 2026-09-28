# OmaRank: benchmarks and rankings. Panel.qml runs <plugin>/omarank-engine
# (Rust); the omarank-dashboard script builds it with cargo and checks a
# provenance stamp it writes. Pattern: a helper in the tree, the dashboard
# patched to run it without the stamp.
{ lib, fetchFromGitHub, rustPlatform, curl, pciutils, inxi }:
let
  src = fetchFromGitHub {
    owner = "ozdil";
    repo = "omarchy-omarank";
    rev = "309c416ffda8980dc445ff8bdde2978503f2b105";
    hash = "sha256-FhOMiyVXt2B6nKg/jMvKZqQtb6Zoywg6sj5rfu3lXME=";
  };
  engine = rustPlatform.buildRustPackage {
    pname = "omarank-engine";
    version = "0-unstable-309c416";
    inherit src;
    cargoHash = "sha256-95XwHjwMZwFlvBWPrbLUvgUG3VV5sWACorLrmT8FeXM=";
    meta.mainProgram = "omarank-engine";
  };
in
{
  inherit src;
  helpers."omarank-engine" = lib.getExe engine;
  postPatch = ''
    substituteInPlace omarank-dashboard \
      --replace-fail 'STAMP="''${DIR}/.engine-provenance"' '/usr/bin/clear 2>/dev/null || true; exec "''${BIN}" "$@"'
  '';
  # The engine runs /usr/bin/curl, lspci and inxi (envfs finds them on PATH).
  packages = [ curl pciutils inxi ];
  meta.description = "Benchmarks and rankings (omarank-engine built with Cargo)";
}
