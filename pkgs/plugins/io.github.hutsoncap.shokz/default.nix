# Shokz: headphone battery and EQ over RFCOMM (bin/shokz-status, Python).
# It uses <plugin>/bin/sdp-rfcomm, when present, to find the channel
# faster (`make` builds it against libbluetooth). Pattern: a helper inside
# the plugin's tree.
{ lib, fetchFromGitHub, stdenv, bluez }:
let
  src = fetchFromGitHub {
    owner = "Hutsoncap";
    repo = "omarchy-shokz";
    rev = "41d16ca7227d80cd072e815a7e1dbc0cd9fdc865";
    hash = "sha256-tmjB/Bjqq+hkR88eB/QXMAmnCTJhDSGkNyNs8GBztq0=";
  };

  sdp-rfcomm = stdenv.mkDerivation {
    pname = "sdp-rfcomm";
    version = "0-unstable-41d16ca";
    inherit src;
    buildInputs = [ bluez ];
    makeFlags = [ "CC=${stdenv.cc.targetPrefix}cc" ];
    installPhase = "install -Dm755 bin/sdp-rfcomm $out/bin/sdp-rfcomm";
    meta.mainProgram = "sdp-rfcomm";
  };
in
{
  inherit src;
  helpers."bin/sdp-rfcomm" = lib.getExe sdp-rfcomm;
  meta.description = "Shokz headphones (sdp-rfcomm built from bin/sdp-rfcomm.c)";
}
