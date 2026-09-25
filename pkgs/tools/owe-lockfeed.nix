{ lib, stdenv, inputs, cmake, qt6 }:

stdenv.mkDerivation {
  pname = "owe-lockfeed";
  version = "0.2.6";
  src = inputs.owe;
  sourceRoot = "source/qml-plugin";

  nativeBuildInputs = [ cmake ];
  buildInputs = [ qt6.qtdeclarative ];
  dontWrapQtApps = true;

  cmakeFlags = [ "-DCMAKE_INSTALL_LIBDIR=lib" ];

  meta = {
    description = "Lock screen video feed (the Owe.LockFeed QML module) for the OWE wallpaper engine";
    homepage = "https://github.com/omacom/owe";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
