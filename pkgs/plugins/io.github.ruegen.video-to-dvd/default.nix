# Video to DVD: Panel.qml runs <plugin>/oma-dvd, a Rust helper that
# drives ffprobe/ffmpeg, dvdauthor, genisoimage and growisofs (found with
# `which`; its install step is pacman). Pattern: a helper inside the
# plugin's tree, with the tools on PATH.
{ lib, fetchFromGitHub, rustPlatform, ffmpeg, dvdauthor, cdrkit, dvdplusrwtools, util-linux, which }:
let
  src = fetchFromGitHub {
    owner = "Ruegen";
    repo = "omarchy-video-to-dvd";
    rev = "1e014a14a3e5f9837c2448aa686f70d111603d57";
    hash = "sha256-j8iGr4e/cwrDorsVxAeE3xlROwV86nnQS9pp4bKC3Fw=";
  };

  oma-dvd = rustPlatform.buildRustPackage {
    pname = "oma-dvd";
    version = "0-unstable-1e014a1";
    inherit src;
    cargoHash = "sha256-Yklvg3it9sYUrv4Wfy44LppnOdTfM4nrXaKYI5Rsr3M=";
    meta.mainProgram = "oma-dvd";
  };
in
{
  inherit src;
  helpers."oma-dvd" = lib.getExe oma-dvd;
  packages = [ ffmpeg dvdauthor cdrkit dvdplusrwtools util-linux which ];
  meta.description = "Burn videos to DVD (oma-dvd built from the repo)";
}
