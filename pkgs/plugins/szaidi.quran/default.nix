# Quran: reading and recitation. Service.qml looks for the Go audio engine
# (quranproxyd + quranctl) in <plugin>/prebuilt/linux-<arch>, where
# install.sh puts release binaries. Pattern: helpers inside the tree.
{ lib, stdenv, fetchFromGitHub, buildGoModule, mpv, ffmpeg, file }:
let
  src = fetchFromGitHub {
    owner = "szaidi-code";
    repo = "quran-plugin";
    rev = "55e61b11af9232813b331578497e3fa78754e463";
    hash = "sha256-ccf5nEwZFvPuOQYfEIi6N7ndXsd6wzLcxMcNlV5qii4=";
  };
  engine = buildGoModule {
    pname = "quran-engine";
    version = "0-unstable-55e61b1";
    inherit src;
    vendorHash = null;
    subPackages = [ "cmd/quranctl" "cmd/quranproxyd" ];
    env.CGO_ENABLED = 0;
  };
  arch = if stdenv.hostPlatform.isAarch64 then "arm64" else "amd64";
in
{
  inherit src;
  helpers."prebuilt/linux-${arch}/quranproxyd" = "${engine}/bin/quranproxyd";
  helpers."prebuilt/linux-${arch}/quranctl" = "${engine}/bin/quranctl";
  # Playback (mpv), media checks (ffprobe, file).
  packages = [ mpv ffmpeg file ];
  meta.description = "Quran reader and recitation (quranproxyd and quranctl built from cmd/)";
}
