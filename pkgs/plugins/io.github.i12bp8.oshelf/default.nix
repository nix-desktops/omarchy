# oShelf: a file shelf whose cards import native/ (module OShelf.Native), a
# C++ QML plugin for drag and drop that `make` builds into
# native/liboshelf-native.so. Built against Quickshell's Qt (nixos-unstable).
# Pattern: a compiled QML plugin inside the plugin's tree.
{ lib, fetchFromGitHub, omarchyUnstable }:
let
  src = fetchFromGitHub {
    owner = "i12bp8";
    repo = "oShelf";
    rev = "eecdec9b94c606a1456c0e999b62ce1a33302360";
    hash = "sha256-uFv7OsT4UZkjtNLu9MJQGefAcT2WTiKtBw1Oyh5C/zk=";
  };

  inherit (omarchyUnstable) qt6;
  native = omarchyUnstable.stdenv.mkDerivation {
    pname = "oshelf-native";
    version = "0-unstable-eecdec9";
    inherit src;
    nativeBuildInputs = [ omarchyUnstable.pkg-config ];
    buildInputs = [ qt6.qtbase qt6.qtdeclarative ];
    dontWrapQtApps = true;
    makeFlags = [ "QT_LIBEXEC=${qt6.qtbase}/libexec" ];
    installPhase = "install -Dm755 native/liboshelf-native.so $out/lib/liboshelf-native.so";
  };
in
{
  inherit src;
  helpers."native/liboshelf-native.so" = "${native}/lib/liboshelf-native.so";
  meta.description = "File shelf (its drag-and-drop QML plugin built against Quickshell's Qt)";
}
