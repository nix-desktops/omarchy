# Sony headphones (WH-1000XM5): Service.qml runs ~/.local/bin/sony-ctl and
# reads the status the sony-headphones-daemon user service writes; setup
# builds both with CMake and installs the unit. Pattern: links in the home,
# the unit included (enabled for the graphical session).
{ lib, stdenv, fetchFromGitHub, cmake, ninja, pkg-config, bluez, dbus }:
let
  src = fetchFromGitHub {
    owner = "andROYdified";
    repo = "omarchy-sony";
    rev = "c0277cf5074391f618150e3f5074ef222fe8c20d";
    hash = "sha256-6JSJ+hbG/oPBSf9IygnKtaxtBcVyzzkm6az4UkjFZRU=";
  };
  omasony = stdenv.mkDerivation {
    pname = "omarchy-sony";
    version = "0.1.0-unstable-c0277cf";
    inherit src;
    nativeBuildInputs = [ cmake ninja pkg-config ];
    buildInputs = [ bluez dbus ];
    cmakeFlags = [ "-DBUILD_TESTING=OFF" ];
  };
  unit = "${src}/daemon/sony-headphones.service";
in
{
  inherit src;
  home.".local/bin/sony-ctl" = "${omasony}/bin/sony-ctl";
  home.".local/bin/sony-headphones-daemon" = "${omasony}/bin/sony-headphones-daemon";
  home.".config/systemd/user/sony-headphones.service" = unit;
  home.".config/systemd/user/graphical-session.target.wants/sony-headphones.service" = unit;
  meta.description = "Sony headphones (sony-ctl and its daemon built with CMake, a user service)";
}
