# Syncthing panel: shared/CoreProcess.qml runs <plugin>/bin/x86_64/syncshell-core,
# a committed static Go build that talks to Syncthing's REST API. Pattern:
# the helper rebuilt from core/, in the tree.
{ lib, fetchFromGitHub, buildGoModule, syncthing, xdg-utils }:
let
  src = fetchFromGitHub {
    owner = "omarchy-QOL";
    repo = "syncshell";
    rev = "7318f1404e765f274df3d079e35d0ad32b5c1701";
    hash = "sha256-vu+Qxu6TnOKkr/2+OWlfeVOOSqtdU6ufqq64uMhXmKE=";
  };
  # The GitHub tarball leaves core/ out (export-ignore): fetch it with git.
  coreSrc = fetchFromGitHub {
    inherit (src) owner repo rev;
    forceFetchGit = true;
    sparseCheckout = [ "core" ];
    hash = "sha256-FagzfUg6lu0StedgdMRDyrcpnzmIKdE0iiDsOIwLRA0=";
  };
  core = buildGoModule {
    pname = "syncshell-core";
    version = "0-unstable-7318f14";
    src = coreSrc;
    modRoot = "core";
    vendorHash = "sha256-qy4wFPjUb3nxiujHUQ6LiKkmJ+EdLVngm9y+tnaJefU=";
    subPackages = [ "cmd/syncshell-core" ];
    env.CGO_ENABLED = 0;
    meta.mainProgram = "syncshell-core";
  };
in
{
  inherit src;
  helpers."bin/x86_64/syncshell-core" = lib.getExe core;
  packages = [ syncthing xdg-utils ];
  meta.description = "Syncthing panel (syncshell-core built from core/)";
}
