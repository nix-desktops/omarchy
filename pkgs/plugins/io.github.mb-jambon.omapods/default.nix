# AirPods Experience: all state comes from the plugin's librepods daemon
# (daemon/, C++/Qt, a fork of librepods with librepods-ctl) as a user
# service; Service.qml runs librepods-ctl from PATH and reads
# ~/.local/state/librepods/status.json. The setup script cmake-builds it
# into ~/.local. Its connection cards import QtQuick3D. Pattern: the daemon
# on PATH with its user unit linked, and QML modules for Quickshell's Qt.
{ lib, stdenv, fetchFromGitHub, cmake, ninja, pkg-config, qt6, openssl, libpulseaudio, omarchyUnstable }:
let
  src = fetchFromGitHub {
    owner = "MB-JAMBON";
    repo = "omarchy-pods";
    rev = "3d770f31fc051e9da86d8dcdd2b62cc76de29112";
    hash = "sha256-HaKEN/eC7dqiLdKh7a8L3rnPr6UA1knTWearv9X4Bp8=";
  };

  librepods = stdenv.mkDerivation {
    pname = "omapods-librepods";
    version = "0-unstable-3d770f3";
    inherit src;
    sourceRoot = "${src.name}/daemon";
    # Its own process: 26.05's Qt.
    nativeBuildInputs = [ cmake ninja pkg-config qt6.wrapQtAppsHook qt6.qttools ];
    buildInputs = [ qt6.qtbase qt6.qtdeclarative qt6.qtconnectivity openssl libpulseaudio ];
    cmakeFlags = [ "-DBUILD_TESTING=OFF" ];
    postPatch = ''
      substituteInPlace librepods.service \
        --replace-fail 'ExecStart=%h/.local/bin/librepods' "ExecStart=$out/bin/librepods"
    '';
    meta.mainProgram = "librepods";
  };
in
{
  inherit src;
  packages = [ librepods ];
  home.".config/systemd/user/librepods.service" = "${librepods}/share/systemd/user/librepods.service";
  home.".config/systemd/user/graphical-session.target.wants/librepods.service" = "${librepods}/share/systemd/user/librepods.service";
  qmlModules = with omarchyUnstable.kdePackages; [ qtquick3d qtquicktimeline ];
  meta.description = "AirPods panel (its librepods daemon built with cmake, user service; QtQuick3D)";
}
