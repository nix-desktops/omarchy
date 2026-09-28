# cliamp visualiser: bands from `cliamp visstream`, else a PulseAudio meter
# (<plugin>/audio-meter, a wrapper that compiles audio-meter.c with cc on
# first use). Pattern: the compiled meter in place of the wrapper.
{ lib, stdenv, fetchFromGitHub, pkg-config, libpulseaudio, cliamp }:
let
  src = fetchFromGitHub {
    owner = "ollieedgeley";
    repo = "quickshell-cliamp-visualiser";
    rev = "8412c287a117d89ae5f412c5c1dba12167682a2c";
    hash = "sha256-eW28kJP1TanZEo1d34bpiKY8o+Z89pbxZsXYn5z79i0=";
  };
  audio-meter = stdenv.mkDerivation {
    pname = "cliamp-audio-meter";
    version = "0-unstable-8412c28";
    inherit src;
    nativeBuildInputs = [ pkg-config ];
    buildInputs = [ libpulseaudio ];
    buildPhase = ''
      $CC -O2 -std=c11 -Wall -Wextra audio-meter.c \
        $(pkg-config --cflags --libs libpulse-simple) -lm -o audio-meter
    '';
    installPhase = "install -Dm755 audio-meter $out/bin/audio-meter";
    meta.mainProgram = "audio-meter";
  };
in
{
  inherit src;
  helpers."audio-meter" = lib.getExe audio-meter;
  packages = [ cliamp ];
  meta.description = "cliamp visualiser (its PulseAudio fallback meter built from audio-meter.c)";
}
