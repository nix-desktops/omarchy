# Note Note: TextInspector.qml imports "../../cpp/build/NoteNote/Native",
# an optional C++ QML module (cpp/, built with CMake against the system
# Qt); without it the editor scans the document's HTML. Built against
# Quickshell's Qt (nixos-unstable). Pattern: a compiled QML module inside
# the plugin's tree.
{ lib, fetchFromGitHub, omarchyUnstable }:
let
  src = fetchFromGitHub {
    owner = "andreivinca";
    repo = "omarchy-note-note";
    rev = "aa60351ed819af533bac3f64d58a2b0b227e67e4";
    hash = "sha256-4H9t1aFDAD8/UuVrbEPgp8JLz43En5VA3DDfZBvKGt4=";
  };

  native = omarchyUnstable.stdenv.mkDerivation {
    pname = "notenote-native";
    version = "0-unstable-aa60351";
    inherit src;
    sourceRoot = "${src.name}/cpp";
    nativeBuildInputs = [ omarchyUnstable.cmake ];
    buildInputs = with omarchyUnstable.qt6; [ qtbase qtdeclarative ];
    dontWrapQtApps = true;
    installPhase = ''
      runHook preInstall
      cp -r NoteNote/Native $out
      runHook postInstall
    '';
  };
in
{
  inherit src;
  # The module's files, one by one (the registry check wants files).
  helpers = lib.genAttrs' [ "qmldir" "libnotenotetext.so" "notenotetext.qmltypes" ]
    (f: lib.nameValuePair "cpp/build/NoteNote/Native/${f}" "${native}/${f}");
  meta.description = "Notes editor (its native QML text inspector built against Quickshell's Qt)";
}
