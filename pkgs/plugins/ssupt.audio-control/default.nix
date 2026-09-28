# Advanced Audio Control: the mixer's backend is
# <plugin>/bin/omarchy-audio-service, shipped prebuilt against libpipewire
# (which doesn't load on NixOS). Its build.rs hashes the plugin's sources
# into the buildId the QML checks, so building the same sources gives the
# same id. Pattern: a helper inside the plugin's tree, replacing the
# prebuilt one.
{ lib, fetchFromGitHub, rustPlatform, pkg-config, pipewire, libpulseaudio }:
let
  src = fetchFromGitHub {
    owner = "ssupt";
    repo = "omarchy-audio-control";
    rev = "f561410e70a71133e39744bcd9091dab184af11c";
    hash = "sha256-ev7/GhSPvJUnRqvLqXzxdsaHCKq8gvEIkTtkB+deCL8=";
  };

  service = rustPlatform.buildRustPackage {
    pname = "omarchy-audio-service";
    version = "0.1.0-unstable-f561410";
    inherit src;
    sourceRoot = "${src.name}/backend";
    cargoHash = "sha256-OaKzrGIreNeoptawZPdAWB8DrLQok5Kes6wBz3G9nfM=";
    nativeBuildInputs = [ pkg-config rustPlatform.bindgenHook ];
    buildInputs = [ pipewire libpulseaudio ];
    # Runs scripts/.audio-common through bash with tools the sandbox lacks.
    checkFlags = [ "--skip=storage::tests::configuration_directory_symlinks_preserve_the_target_and_lock" ];
    # The QML refuses a backend whose buildId isn't the release's.
    postInstall = ''
      grep -q f60c7acb0850c90f63d5a68cf3a62bc20fb96b25e8062e0705422ba3cb56ff0c $out/bin/omarchy-audio-service
    '';
    meta.mainProgram = "omarchy-audio-service";
  };
in
{
  inherit src;
  helpers."bin/omarchy-audio-service" = lib.getExe service;
  meta.description = "PipeWire mixer (omarchy-audio-service built from backend/)";
}
