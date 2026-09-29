# On-Screen Keyboard: every key press runs <plugin>/bin/osk-input, a
# script that compiles native/osk-input.c (Wayland virtual keyboard) into
# ~/.cache on first use. Pattern: the script replaced by one that runs the
# Nix-built binary.
{ lib, fetchFromGitHub, stdenv, writeShellScript, pkg-config, wayland, wayland-scanner, libxkbcommon }:
let
  src = fetchFromGitHub {
    owner = "mtolhuys";
    repo = "omarchy-onscreen-keyboard";
    rev = "a41b45a75261a89f5a9b7b0b9c75cb099cbcd1b5";
    hash = "sha256-Uqtrs6aPDi11p4UUdQVuhiSBW71zO8oJA/eWlUdN5e0=";
  };

  osk-input = stdenv.mkDerivation {
    pname = "osk-input";
    version = "0.9.2-unstable-a41b45a";
    inherit src;
    nativeBuildInputs = [ pkg-config wayland-scanner ];
    buildInputs = [ wayland libxkbcommon ];
    buildPhase = ''
      runHook preBuild
      wayland-scanner client-header native/virtual-keyboard-unstable-v1.xml virtual-keyboard-unstable-v1-client-protocol.h
      wayland-scanner private-code native/virtual-keyboard-unstable-v1.xml virtual-keyboard-unstable-v1-protocol.c
      $CC -std=c11 -O2 -Wall -Wextra $(pkg-config --cflags wayland-client xkbcommon) -I. \
        native/osk-input.c virtual-keyboard-unstable-v1-protocol.c \
        $(pkg-config --libs wayland-client xkbcommon) -o osk-input
      runHook postBuild
    '';
    installPhase = "install -Dm755 osk-input $out/bin/osk-input";
    meta.mainProgram = "osk-input";
  };

  # bin/osk-input's interface: --prepare, or MODIFIER_MASK EVDEV_KEYCODE.
  wrapper = writeShellScript "osk-input" ''
    if [ "''${1:-}" = --prepare ] && [ $# = 1 ]; then exit 0; fi
    exec ${lib.getExe osk-input} "$@"
  '';
in
{
  inherit src;
  helpers."bin/osk-input" = wrapper;
  meta.description = "On-screen keyboard (osk-input built from native/)";
}
