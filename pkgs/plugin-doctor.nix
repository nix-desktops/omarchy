# `omarchy plugin doctor`: what a shell plugin needs on NixOS
# (bin/omarchy-plugin-doctor.py). Installed over the omarchy package's
# commands like the other NixOS commands; the metadata comments come
# first so `omarchy plugin doctor` and `omarchy help` find it.
#
#   quickshell   the shell's Quickshell: the QML modules it can import
#   qmlModules   more QML modules on the shell's QML_IMPORT_PATH
#                (omarchy.qmlModules)
{ lib, runCommand, writeTextFile, writeText, bash, python3, python3Packages, callPackage
, quickshell, qmlModules ? [ ] }:

let
  programsDb = callPackage ./programs-db.nix { };

  # Every QML module the shell can import: Quickshell's own and the Qt
  # modules its wrapper puts on the import path, plus qmlModules.
  qmlList = runCommand "omarchy-shell-qml-modules" { } ''
    {
      grep -aoE '/nix/store/[a-z0-9]{32}-[^/:" ]+/lib/qt-6/qml' ${quickshell}/bin/quickshell || true
      echo ${quickshell}/lib/qt-6/qml
      ${lib.concatMapStrings (m: "echo ${m}/lib/qt-6/qml; echo ${m}/lib/qt6/qml\n") qmlModules}
    } | sort -u | while read -r dir; do
      [ -d "$dir" ] || continue
      (cd "$dir" && find . -name qmldir -printf '%h\n') | sed -e 's#^\./##' -e 's#/#.#g'
    done | sort -u >$out
    grep -qx QtQuick $out && grep -qx Quickshell $out
  '';

  pyPackages = writeText "python3-packages" (lib.concatStringsSep "\n" (builtins.attrNames python3Packages) + "\n");
in
writeTextFile {
  name = "omarchy-plugin-doctor";
  executable = true;
  destination = "/bin/omarchy-plugin-doctor";
  text = ''
    #!${bash}/bin/bash
    # omarchy:summary=Check what a shell plugin needs on NixOS: missing commands and their nixpkgs packages
    # omarchy:group=plugin
    # omarchy:name=doctor
    # omarchy:args=[id|path ...] [--json] [--verbose]
    # omarchy:examples=omarchy plugin doctor acme.weather
    export OMARCHY_PROGRAMS_DB=''${OMARCHY_PROGRAMS_DB-${programsDb}/programs.sqlite}
    export OMARCHY_QML_MODULES=''${OMARCHY_QML_MODULES-${qmlList}}
    export OMARCHY_PY_PACKAGES=''${OMARCHY_PY_PACKAGES-${pyPackages}}
    exec ${python3}/bin/python3 ${../bin/omarchy-plugin-doctor.py} "$@"
  '';
  passthru = { inherit programsDb qmlList; };
  meta = {
    description = "Checks what an Omarchy shell plugin needs on NixOS";
    mainProgram = "omarchy-plugin-doctor";
  };
}
