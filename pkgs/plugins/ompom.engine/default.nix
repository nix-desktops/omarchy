# Ompom Engine: a pomodoro engine and break overlay. Its writing surfaces
# import MarkdownHighlight, a C++ QML module from the author's omvision
# repo (highlighter/, built with moc + g++ by build.sh and deployed into
# native/ by hand); without it the overlay loses its markdown styling.
# Pattern: a QML module built against Quickshell's Qt.
{ lib, fetchFromGitHub, omarchyUnstable }:
let
  src = fetchFromGitHub {
    owner = "OuttaSpaceTime";
    repo = "ompom-engine";
    rev = "bfc25a5094e7474fec7d402c8b6e5ff9e5b1ae05";
    hash = "sha256-5IbqOEXV6m1nJyLwTRNhNdj3VPvrwFHEdrM3Q/zWsNc=";
  };

  inherit (omarchyUnstable) stdenv pkg-config;
  inherit (omarchyUnstable.qt6) qtbase qtdeclarative;

  # omvision's highlighter/build.sh, as a derivation.
  markdownhighlight = stdenv.mkDerivation {
    pname = "omvision-markdownhighlight";
    version = "0-unstable-ac72e97";
    src = fetchFromGitHub {
      owner = "OuttaSpaceTime";
      repo = "omvision";
      rev = "ac72e97469c51fcec66e915b65f24a152bf90e5f";
      hash = "sha256-x1pg1D6fLtwVrVaGALMwvVx+WXNHrF3VioRASEkxXxo=";
    };
    sourceRoot = "source/highlighter";
    nativeBuildInputs = [ pkg-config ];
    buildInputs = [ qtbase qtdeclarative ];
    dontWrapQtApps = true;
    buildPhase = ''
      ${qtbase}/libexec/moc markdownhighlighter.h -o moc_markdownhighlighter.cpp
      ${qtbase}/libexec/moc plugin.h -o moc_plugin.cpp
      $CXX -std=c++17 -fPIC -shared -O2 -fvisibility=hidden -fvisibility-inlines-hidden \
        $(pkg-config --cflags Qt6Quick Qt6Qml Qt6Gui Qt6Core) -I. \
        markdownhighlighter.cpp plugin.cpp moc_markdownhighlighter.cpp moc_plugin.cpp \
        $(pkg-config --libs Qt6Quick Qt6Qml Qt6Gui Qt6Core) -o libmarkdownhighlight.so
    '';
    installPhase = ''
      dir=$out/lib/qt-6/qml/MarkdownHighlight
      install -Dm755 libmarkdownhighlight.so $dir/libmarkdownhighlight.so
      printf 'module MarkdownHighlight\nplugin markdownhighlight\n' > $dir/qmldir
    '';
  };
in
{
  inherit src;
  qmlModules = [ markdownhighlight ];
  meta.description = "Pomodoro engine (omvision's MarkdownHighlight QML module built against Quickshell's Qt)";
}
