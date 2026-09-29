# RAM speed test: Panel.qml runs <plugin>/ram-speedtest, a script compiling
# ram-speedtest.c with cc into ~/.cache on first use. Pattern: the script
# replaced by the program, built with Nix.
{ lib, stdenv, fetchFromGitHub }:
let
  src = fetchFromGitHub {
    owner = "phedoreanu";
    repo = "omarchy-ram-speedtest";
    rev = "d2fa57219756f34c3553ef818eb06f10b1a76a0e";
    hash = "sha256-rUMD5hql4/BaOymfftods+zmZOwC4WjINFhFNjMxNbk=";
  };

  ram-speedtest = stdenv.mkDerivation {
    pname = "ram-speedtest";
    version = "0-unstable-d2fa572";
    inherit src;
    buildPhase = "$CC -O2 -pthread -o ram-speedtest-bin ram-speedtest.c";
    installPhase = "install -Dm755 ram-speedtest-bin $out/bin/ram-speedtest";
    meta.mainProgram = "ram-speedtest";
  };
in
{
  inherit src;
  helpers."ram-speedtest" = lib.getExe ram-speedtest;
  meta.description = "RAM bandwidth benchmark (ram-speedtest.c built with Nix)";
}
