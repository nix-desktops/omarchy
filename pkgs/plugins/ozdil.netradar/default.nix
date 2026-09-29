# NetRadar: LAN scanner. Panel.qml runs <plugin>/netradar-engine; the
# scripts and the standalone window look in ~/.local/bin (upstream builds
# it with cargo). Pattern: a helper in the plugin's tree and a home link.
{ lib, fetchFromGitHub, rustPlatform, iproute2 }:
let
  src = fetchFromGitHub {
    owner = "ozdil";
    repo = "omarchy-netradar";
    rev = "ad0ba609d95f05d832d23b5e6f804a4b44d455a6";
    hash = "sha256-U/Gwu/2vhkKKjDUa/KhMj3AzXUorkupSBZT1P0GsXIg=";
  };

  engine = rustPlatform.buildRustPackage {
    pname = "netradar-engine";
    version = "1.0.0-unstable-ad0ba60";
    inherit src;
    cargoHash = "sha256-2U91BMV0EYdS4ay3fa5mszKLgukukg36pZH3tf409EE=";
    # These run `cargo run` and scan the network: not in the sandbox.
    checkFlags = [ "--skip=test_cli_scan_json_output" "--skip=test_cli_status" ];
    meta.mainProgram = "netradar-engine";
  };
in
{
  inherit src;
  helpers."netradar-engine" = lib.getExe engine;
  home.".local/bin/netradar-engine" = lib.getExe engine;
  packages = [ iproute2 ];
  meta.description = "LAN radar (netradar-engine built from the repo)";
}
