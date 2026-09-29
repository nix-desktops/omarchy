# Mote: the bar button launches Mote, a standalone egui pixel-art editor
# (the repo's crate), as `mote` from PATH (upstream's install.sh builds it
# into ~/.local/bin). Pattern: a helper on PATH.
{ lib, fetchFromGitHub, rustPlatform, libGL, libxkbcommon, wayland, libx11, libxcursor, libxi, libxrandr }:
let
  src = fetchFromGitHub {
    owner = "benryanx";
    repo = "mote";
    rev = "e7bbbbb6f8f5781008a071f563a99c6cf561c2c6";
    hash = "sha256-QF5PkcWQfykp4NprHjkUl6TfdcIR8yi9WAhHRagLeH0=";
  };

  mote = rustPlatform.buildRustPackage {
    pname = "mote";
    version = "0.2.0-rc.1-unstable-e7bbbbb";
    inherit src;
    cargoHash = "sha256-Ok+uCwliivqdVNyCrMBJ23cRgLC4fI1UOvDKhIYugzs=";
    # These run /usr/bin/yes and other fixed paths the sandbox lacks.
    checkFlags = [
      "--skip=agent::tests::restrictive_flags_and_stdin_output"
      "--skip=agent::tests::running_process_cancels_and_failures_hide_output"
    ];
    # winit and glow dlopen these.
    postFixup = ''
      patchelf --add-rpath ${lib.makeLibraryPath [
        libGL libxkbcommon wayland libx11 libxcursor libxi libxrandr
      ]} $out/bin/mote
    '';
    meta.mainProgram = "mote";
  };
in
{
  inherit src;
  packages = [ mote ];
  meta.description = "Pixel-art editor launcher (mote built from source, on PATH)";
}
