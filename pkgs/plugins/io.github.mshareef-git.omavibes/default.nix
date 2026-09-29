# OmaVibes: keyboard sounds from <plugin>/bin/wayvibes, committed as a
# prebuilt glibc binary; its source is third_party/wayvibes (C++, libevdev,
# miniaudio, which dlopens PulseAudio/ALSA). Pattern: a helper inside the
# plugin's tree, built from source. Reading /dev/input needs the `input` group.
{ lib, stdenv, fetchFromGitHub, libevdev, nlohmann_json, libpulseaudio, alsa-lib, procps }:
let
  src = fetchFromGitHub {
    owner = "mshareef-git";
    repo = "omavibes";
    rev = "aae7d4cfc8f7ed06a9b6544c425d9497c2f49590";
    hash = "sha256-mMSSVuBWqvtBax+VgYMr837Sd6Lf2wKyuSi6EcW01rI=";
  };

  wayvibes = stdenv.mkDerivation {
    pname = "wayvibes";
    version = "0-unstable-aae7d4c";
    inherit src;
    sourceRoot = "${src.name}/third_party/wayvibes";
    # The committed binary would pass for up to date with make.
    postPatch = "rm wayvibes";
    buildInputs = [ libevdev nlohmann_json ];
    NIX_CFLAGS_COMPILE = "-I${lib.getDev libevdev}/include";
    installPhase = "install -Dm755 wayvibes $out/bin/wayvibes";
    # miniaudio opens its audio backends at run time.
    postFixup = ''
      patchelf --add-rpath ${lib.makeLibraryPath [ libpulseaudio alsa-lib ]} $out/bin/wayvibes
    '';
    meta.mainProgram = "wayvibes";
  };
in
{
  inherit src;
  helpers."bin/wayvibes" = lib.getExe wayvibes;
  packages = [ procps ];
  # /dev/input: the NixOS module adds the user to the group.
  extraGroups = [ "input" ];
  meta.description = "Mechanical keyboard sounds (wayvibes built from third_party/wayvibes)";
}
