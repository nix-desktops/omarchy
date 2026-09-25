# Omarchy's Qt Quick apps (omacut, omacalc, omawrite): qmake projects built
# the way their bin/build does, with the desktop entry and icon from their
# pkgbuild/ directory (omacalc's from omacom/omarchy-pkgs).
{ lib, stdenv, qt6, pname, version, src, description
, extraQt ? [ ], runtimePath ? [ ], launcher ? "${src}/pkgbuild" }:

stdenv.mkDerivation {
  inherit pname version src;

  nativeBuildInputs = [ qt6.qmake qt6.wrapQtAppsHook ];
  buildInputs = [ qt6.qtbase qt6.qtdeclarative qt6.qtwayland ]
    ++ map (m: qt6.${m}) extraQt;

  qtWrapperArgs = lib.optionals (runtimePath != [ ])
    [ "--prefix" "PATH" ":" (lib.makeBinPath runtimePath) ];

  configurePhase = ''
    runHook preConfigure
    mkdir build
    cd build
    qmake ../${pname}.pro
    runHook postConfigure
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 ${pname} $out/bin/${pname}
    install -Dm644 ${launcher}/${pname}.desktop $out/share/applications/${pname}.desktop
    install -Dm644 ${launcher}/${pname}.svg $out/share/icons/hicolor/scalable/apps/${pname}.svg
    runHook postInstall
  '';

  meta = {
    inherit description;
    homepage = "https://github.com/omacom/${pname}";
    license = with lib.licenses; [ mit ofl ];
    mainProgram = pname;
    platforms = lib.platforms.linux;
  };
}
