# Wiggle: shake the pointer to find it. Wiggle.qml runs
# <plugin>/scripts/wiggle-monitor, an evdev reader shipped prebuilt for
# Debian's loader. Pattern: the helper rebuilt from its C source, in the tree.
# It reads /dev/input/event*: the user must be in the `input` group.
{ lib, stdenv, fetchFromGitHub, pkg-config, libevdev, glib }:
let
  src = fetchFromGitHub {
    owner = "sanjyay";
    repo = "wiggle";
    rev = "03524f9052434a5fd7d09b35d49a53350c496788";
    hash = "sha256-21m2jYKYXC0BpqbHiKv6oDAfjjf2dtMDxAhY09TO9r8=";
  };
  wiggle-monitor = stdenv.mkDerivation {
    pname = "wiggle-monitor";
    version = "0-unstable-03524f9";
    inherit src;
    nativeBuildInputs = [ pkg-config ];
    buildInputs = [ libevdev ];
    buildPhase = ''
      $CC -O2 -o wiggle-monitor scripts/wiggle-monitor.c \
        $(pkg-config --cflags --libs libevdev) -lm
    '';
    installPhase = "install -Dm755 wiggle-monitor $out/bin/wiggle-monitor";
    meta.mainProgram = "wiggle-monitor";
  };
in
{
  inherit src;
  helpers."scripts/wiggle-monitor" = lib.getExe wiggle-monitor;
  # gsettings (the cursor theme and size).
  packages = [ glib ];
  # /dev/input: the NixOS module adds the user to the group.
  extraGroups = [ "input" ];
  meta.description = "Shake to find the pointer (wiggle-monitor built from its C source)";
}
