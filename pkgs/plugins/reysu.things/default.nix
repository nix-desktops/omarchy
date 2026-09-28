# Things: Things 3 (Cultured Code) lists. Panel.qml runs `things3 --json …`
# from PATH, the repo's own things3-cloud fork, which setup cargo-builds into
# /usr/local/bin. Pattern: the helper on PATH. Log in once with
# `things3 set-auth`.
{ fetchFromGitHub, rustPlatform, lib, jq }:
let
  src = fetchFromGitHub {
    owner = "reysu";
    repo = "omarchy-things";
    rev = "d7cbfc4108f2116796ae72717f813a739eeca392";
    hash = "sha256-d8jeW6AIe7bP4lmewecgED/RdO2zc/eSiEinhC9JZd8=";
  };
  things3 = rustPlatform.buildRustPackage {
    pname = "things3-cloud";
    version = "0.8.3-unstable-d7cbfc4";
    inherit src;
    sourceRoot = "${src.name}/things3-cloud";
    cargoHash = "sha256-sgDZb2h/DqJc3PMVksGlT6cH8n73GObNoH3RNdQMejU=";
    # trycmd looks for the binary under target/release; Nix builds into
    # target/<triple>/release.
    checkFlags = [ "--skip=cli_trycmd_" ];
    meta.mainProgram = "things3";
  };
in
{
  inherit src;
  packages = [ things3 jq ];
  meta.description = "Things 3 lists (things3, the bundled things3-cloud, on PATH)";
}
