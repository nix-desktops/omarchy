# LocalSend: receive and send with LocalSend devices. Receiver.qml runs
# <plugin>/bin/localsend-controller, a launcher that downloads a prebuilt
# controller into ~/.cache. Pattern: the controller built from controller/
# in the launcher's place.
{ lib, fetchFromGitHub, rustPlatform, pkg-config, openssl, util-linux, wl-clipboard }:
let
  src = fetchFromGitHub {
    owner = "cryptobredda";
    repo = "omarchy-localsend";
    rev = "52ddbdda6da02261b3f356374d1893a7f2e3b015";
    hash = "sha256-27r83Hg0bfZTXGWLqHxzPdq3KMoYhWHSmnnoLC00m+c=";
  };
  controller = rustPlatform.buildRustPackage {
    pname = "localsend-controller";
    version = "0-unstable-52ddbdd";
    inherit src;
    sourceRoot = "${src.name}/controller";
    cargoHash = "sha256-e7Q/KZ0K9dQXi/EvCeSB5KdBfxInPIzuQeAIPyT0qfQ=";
    nativeBuildInputs = [ pkg-config ];
    buildInputs = [ openssl ];
    meta.mainProgram = "localsend-controller";
  };
in
{
  inherit src;
  helpers."bin/localsend-controller" = lib.getExe controller;
  # setpriv (runs it), wl-copy/wl-paste.
  packages = [ util-linux wl-clipboard ];
  meta.description = "LocalSend receiver and sender (localsend-controller built from controller/)";
}
