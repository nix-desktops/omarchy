# Quick Bridge: QR upload/share/proxy over a Cloudflare quick tunnel.
# Every action runs <plugin>/scripts/quickbridge, which cargo-builds the
# Rust helper into ~/.cache on first use. Pattern: the launcher patched to
# exec the Nix-built helper.
{ lib, fetchFromGitHub, rustPlatform, wl-clipboard }:
let
  src = fetchFromGitHub {
    owner = "cfaulkingham";
    repo = "quickbridge";
    rev = "3deba6199f6b08007769ae6bdca9d9ccd0a94bee";
    hash = "sha256-NHpc+KkjrxM7D8+bq8/3iPCvOOO3N0rvRwh0RI51+sA=";
  };
  quickbridge = rustPlatform.buildRustPackage {
    pname = "quickbridge";
    version = "1.0.0-unstable-3deba61";
    inherit src;
    cargoHash = "sha256-jeGu2YdVxSUlYaPSQAJuFKH36oo8SvR1XVjJoj0/bjs=";
    postPatch = ''
      substituteInPlace src/share.rs \
        --replace-fail '"/usr/bin/wl-paste"' '"${wl-clipboard}/bin/wl-paste"'
    '';
    meta.mainProgram = "quickbridge";
  };
in
{
  inherit src;
  # Skip the build (and its ~/.cache copy with its owner/mode checks).
  postPatch = ''
    substituteInPlace scripts/quickbridge \
      --replace-fail ': "''${HOME:?}"' ': "''${HOME:?}"; exec ${lib.getExe quickbridge} "$@"'
  '';
  meta.description = "Quick Bridge share tunnel (quickbridge built with Cargo, run by scripts/quickbridge)";
}
