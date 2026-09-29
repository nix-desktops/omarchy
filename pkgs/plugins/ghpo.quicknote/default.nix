# Crypto Notes: quicknote.sh compiles quicknote-crypto.c (libsodium) next
# to itself on first use and execs it; play-music.sh does the same for the
# help music player (ALSA). Pattern: helpers inside the plugin's tree.
{ lib, fetchFromGitHub, stdenv, libsodium, alsa-lib }:
let
  src = fetchFromGitHub {
    owner = "ghpo";
    repo = "ghpo.quicknote";
    rev = "22ac320e4f6ae7be9d06f8563d35d851821c940c";
    hash = "sha256-rxFJcZKwSRGbKZSR2xgR9HYmJ1+scq8WTOVZJvyUUug=";
  };

  helpers = stdenv.mkDerivation {
    pname = "quicknote-helpers";
    version = "0-unstable-22ac320";
    inherit src;
    buildInputs = [ libsodium alsa-lib ];
    buildPhase = ''
      runHook preBuild
      $CC -O2 -o quicknote-crypto quicknote-crypto.c -lsodium
      $CC -O2 -o quicknote-audio quicknote-audio.c -lasound
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      install -Dm755 -t $out/bin quicknote-crypto quicknote-audio
      runHook postInstall
    '';
  };
in
{
  inherit src;
  helpers = {
    "quicknote-crypto" = "${helpers}/bin/quicknote-crypto";
    "quicknote-audio" = "${helpers}/bin/quicknote-audio";
  };
  meta.description = "Encrypted quick notes (quicknote-crypto, quicknote-audio built from their C files)";
}
