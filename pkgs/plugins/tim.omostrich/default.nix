# Omostrich: a Nostr key-custody daemon with the panel as its control UI.
# The QML runs `node ~/Projects/omostrich/bin/ctl.mjs` and the user unit
# `node ~/Projects/omostrich/daemon/daemon.mjs` (a checkout with npm
# dependencies). Pattern: the checkout built with buildNpmPackage, the QML
# and the unit pointed at it, the unit enabled.
{ lib, fetchFromGitHub, buildNpmPackage, runCommand, nodejs, zenity }:
let
  src = fetchFromGitHub {
    owner = "ninepointlabs";
    repo = "omostrich";
    rev = "2161745ab24a694d4a5c1bdfefde1f50ff291e59";
    hash = "sha256-TSHeaQGgp6OArLH6GBhxt5P+IbQiZOjoXOazemnrLuE=";
  };
  omostrich = buildNpmPackage {
    pname = "omostrich";
    version = "0.2.0-unstable-2161745";
    inherit src;
    npmDepsHash = "sha256-oVVsFDMhMLj/CuMx13k76Q8+Kvi0+beWastaAakfywU=";
    dontNpmBuild = true;
  };
  root = "${omostrich}/lib/node_modules/omostrich";
  # Its ReadWritePaths are made before it starts (userServices does that).
  unit = runCommand "omostrich.service" { } ''
    substitute ${src}/omostrich.service $out \
      --replace-fail 'ExecStart=node %h/Projects/omostrich/daemon/daemon.mjs' \
        'ExecStart=${lib.getExe nodejs} ${root}/daemon/daemon.mjs'
  '';
in
{
  inherit src;
  postPatch = ''
    substituteInPlace Panel.qml ComposeOverlay.qml \
      --replace-fail 'Quickshell.env("HOME") + "/Projects/omostrich/bin/ctl.mjs"' '"${root}/bin/ctl.mjs"'
  '';
  userServices."omostrich.service" = unit;
  packages = [ nodejs zenity ];
  meta.description = "Nostr signer (its daemon built with buildNpmPackage, a user service)";
}
