# Bose NC 700: Service.qml talks to $XDG_RUNTIME_DIR/bose-700.sock, a user
# socket unit whose service runs ~/.local/bin/bose-700-daemon (C++, BMAP
# over Bluetooth); upstream's setup builds and installs them (pacman,
# sudo). Pattern: links in the home and user units (socket enabled), the
# service pointed at the store.
{ lib, fetchFromGitHub, stdenv, cmake, ninja, pkg-config, bluez, systemdLibs, runCommand }:
let
  src = fetchFromGitHub {
    owner = "NIPSEN";
    repo = "omarchy-bose-700";
    rev = "fff3aa035d178c12e4624eddfab9dce76a91d813";
    hash = "sha256-xMXQrMcGfr8mQmdPExb+PZo8FAZS4BhibCBwFyd1S8o=";
  };

  bose = stdenv.mkDerivation {
    pname = "omarchy-bose-700";
    version = "0.1.0-unstable-fff3aa0";
    inherit src;
    nativeBuildInputs = [ cmake ninja pkg-config ];
    buildInputs = [ bluez systemdLibs ];
    # Tools run only by absolute, root-owned paths.
    postPatch = ''
      substituteInPlace daemon/src/BluetoothManager.cpp \
        --replace-fail '"/usr/bin/bluetoothctl"' '"${bluez}/bin/bluetoothctl"'
    '';
  };

  service = runCommand "bose-700.service" { } ''
    substitute ${src}/daemon/bose-700.service $out \
      --replace-fail '%h/.local/bin/bose-700-daemon' '${bose}/bin/bose-700-daemon'
  '';
in
{
  inherit src;
  home = {
    ".local/bin/bose-700-daemon" = "${bose}/bin/bose-700-daemon";
    ".local/bin/bose-700-ctl" = "${bose}/bin/bose-700-ctl";
  };
  # Socket-activated: the socket enabled, the service started through it.
  userServices = {
    "bose-700.service" = { source = service; wantedBy = [ ]; };
    "bose-700.socket" = "${src}/daemon/bose-700.socket";
  };
  meta.description = "Bose NC 700 headphones (bose-700-daemon built with CMake, as a socket-activated user unit)";
}
