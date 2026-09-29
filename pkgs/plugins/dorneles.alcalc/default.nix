# ALcalc: a paper-tape calculator. The bar widget and panel are QML plus
# scripts/alcalc-state.py; right-click runs `alcalc`, the standalone Qt app
# install.sh builds (cmake) into ~/.local/bin. Pattern: the app on PATH,
# built against Quickshell's Qt (nixos-unstable) like everything Qt here.
{ fetchFromGitHub, omarchyUnstable }:
let
  src = fetchFromGitHub {
    owner = "jvlianodorneles";
    repo = "alcalc";
    rev = "5bd48948aa23f54d4029f6922c875f6cea3181cc";
    hash = "sha256-mI2w1McnSi8T0g8rKJJpzuyHFZ6JPldEWjPviwMQ3W8=";
  };
  inherit (omarchyUnstable) stdenv cmake qt6;
  alcalc = stdenv.mkDerivation {
    pname = "alcalc";
    version = "0-unstable-5bd4894";
    inherit src;
    nativeBuildInputs = [ cmake qt6.wrapQtAppsHook ];
    buildInputs = [ qt6.qtbase qt6.qtdeclarative ];
    meta.mainProgram = "alcalc";
  };
in
{
  inherit src;
  packages = [ alcalc ];
  meta.description = "Paper-tape calculator (the alcalc Qt app built with CMake, on PATH)";
}
