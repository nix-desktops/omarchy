# Surfshark VPN: the widget polls <plugin>/bin/surfshark-ctl, committed as a
# prebuilt glibc binary; its source is surfshark-ctl-rs/. Pattern: a helper
# inside the plugin's tree, built from source.
{ lib, fetchFromGitHub, rustPlatform, wireguard-tools, curl }:
let
  src = fetchFromGitHub {
    owner = "Djkawada";
    repo = "omarchy-surfshark-vpn";
    rev = "39699d05374c3db31d1d9ec5915d860998ad7443";
    hash = "sha256-CcG1SKVJnueBOdFhwGc0I1+L0ttMor4ECv4aNSZMuSE=";
  };

  surfshark-ctl = rustPlatform.buildRustPackage {
    pname = "surfshark-ctl";
    version = "1.0.0-unstable-39699d0";
    inherit src;
    sourceRoot = "${src.name}/surfshark-ctl-rs";
    cargoHash = "sha256-4HgEpGRUrT6WLdVcu8kW6pnk8+E+8XdAfNurxNmu4Io=";
    meta.mainProgram = "surfshark-ctl";
  };
in
{
  inherit src;
  helpers."bin/surfshark-ctl" = lib.getExe surfshark-ctl;
  # It runs nmcli (NetworkManager, the system's), wg and curl.
  packages = [ wireguard-tools curl ];
  meta.description = "Surfshark VPN widget (surfshark-ctl built from surfshark-ctl-rs/)";
}
