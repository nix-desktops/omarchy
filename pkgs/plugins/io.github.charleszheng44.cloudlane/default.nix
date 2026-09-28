# Cloudlane: the bar widget launches the `cloudlane` app (a C++/Qt NetEase
# Cloud Music client in the same repo, "requires a separate app build") and
# controls it over MPRIS. Its own process, so 26.05's Qt. Pattern: a
# package on PATH.
{ lib, stdenv, fetchFromGitHub, qt6, pkg-config, mpv, libsecret, openssl, qrencode, taglib, zlib }:
let
  src = fetchFromGitHub {
    owner = "charleszheng44";
    repo = "cloudlane";
    rev = "0b286c6e55e6e6d235416a6cfb33fd36bc69f6c8";
    hash = "sha256-s2pJer0QhqTEWjR+ciFxI+VfDorkILJ2N+/lCFTrxt4=";
  };

  cloudlane = stdenv.mkDerivation {
    pname = "cloudlane";
    version = "0.1.0-unstable-0b286c6";
    inherit src;
    nativeBuildInputs = [ qt6.qmake qt6.wrapQtAppsHook pkg-config ];
    buildInputs = [ qt6.qtbase qt6.qtdeclarative mpv libsecret openssl qrencode taglib zlib ];
    installPhase = ''
      runHook preInstall
      install -Dm755 cloudlane $out/bin/cloudlane
      install -Dm644 packaging/io.github.charleszheng44.Cloudlane.desktop -t $out/share/applications
      install -Dm644 packaging/io.github.charleszheng44.Cloudlane.svg -t $out/share/icons/hicolor/scalable/apps
      runHook postInstall
    '';
    meta.mainProgram = "cloudlane";
  };
in
{
  inherit src;
  packages = [ cloudlane ];
  meta.description = "Cloudlane music app launcher and MPRIS controls (the app built with qmake, on PATH)";
}
