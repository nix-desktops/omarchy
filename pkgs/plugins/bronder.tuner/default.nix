# Chromatic Tuner: bin/tuner-pipeline pipes parec into a pitch detector
# (bin/tuner.c, libc + libm) that it compiles with gcc into ~/.cache on
# first use. Built here, and the pipeline pointed at it. Pattern: a build
# step at first run patched to a store path.
{ lib, stdenv, fetchFromGitHub, pulseaudio }:
let
  src = fetchFromGitHub {
    owner = "bronder";
    repo = "omarchy-tuner-v2";
    rev = "d727d3bc0f8cc21ffe85f99517e9e5a3d88e6065";
    hash = "sha256-Y4Y/SxuvU/iHbOKZLoovoXOqXAB2YnWVATOch0TUwkE=";
  };

  tuner = stdenv.mkDerivation {
    pname = "omarchy-tuner";
    version = "0-unstable-d727d3b";
    inherit src;
    buildPhase = "$CC -O2 -Wall -o tuner bin/tuner.c -lm";
    installPhase = "install -Dm755 tuner $out/bin/tuner";
    meta.mainProgram = "tuner";
  };
in
{
  inherit src;
  postPatch = ''
    substituteInPlace bin/tuner-pipeline \
      --replace-fail 'bin=$cache/tuner-$src_hash' 'bin=${lib.getExe tuner}'
  '';
  packages = [ pulseaudio ]; # parec, pactl
  meta.description = "Chromatic tuner (its pitch detector built from bin/tuner.c)";
}
