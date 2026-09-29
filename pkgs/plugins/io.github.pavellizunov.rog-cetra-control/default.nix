# ROG Cetra Control: ASUS ROG Cetra earbuds over USB HID and Bluetooth. The
# QML runs four C helpers from <plugin>/bin (Qt.resolvedUrl), which the
# plugin's `setup` compiles with cc and pkg-config. They open /dev/hidraw*,
# which needs the user to have access (uaccess or a udev rule). Pattern:
# helpers inside the plugin's tree.
{ lib, stdenv, fetchFromGitHub, pkg-config, hidapi, libpulseaudio, bluez }:
let
  src = fetchFromGitHub {
    owner = "PavelLizunov";
    repo = "omarchy-rog-cetra-control";
    rev = "9b8226ae1ecea88b64cec01bcbf60f9ff4840017";
    hash = "sha256-fRAKavLIII3T/lAAtOsQ1g0ro5/6KvQ+AQHB2PnP2O8=";
  };

  names = [ "cetra-status" "cetra-watch" "cetra-peak" "cetra-bt-read" ];
  cetra = stdenv.mkDerivation {
    pname = "rog-cetra-helpers";
    version = "0-unstable-9b8226a";
    inherit src;
    nativeBuildInputs = [ pkg-config ];
    buildInputs = [ hidapi libpulseaudio bluez ];
    # As `setup` builds them.
    buildPhase = ''
      cc -O2 -Wall -Wextra -o cetra-status cetra-status.c $(pkg-config --cflags --libs hidapi-hidraw)
      cc -O2 -Wall -Wextra -o cetra-watch cetra-watch.c $(pkg-config --cflags --libs hidapi-hidraw)
      cc -O2 -Wall -Wextra -o cetra-peak cetra-peak.c $(pkg-config --cflags --libs libpulse) -lm
      cc -O2 -Wall -Wextra -o cetra-bt-read cetra-bt-read.c $(pkg-config --cflags --libs bluez)
    '';
    doCheck = true;
    # cetra-bt-read's opens a Bluetooth socket, which the sandbox lacks.
    checkPhase = lib.concatMapStrings (n: "./${n} --selftest\n") (lib.remove "cetra-bt-read" names);
    installPhase = lib.concatMapStrings (n: "install -Dm755 ${n} $out/bin/${n}\n") names;
  };
in
{
  inherit src;
  helpers = lib.genAttrs' names (n: lib.nameValuePair "bin/${n}" "${cetra}/bin/${n}");
  meta.description = "ROG Cetra earbuds (its four C helpers built as its setup does)";
}
