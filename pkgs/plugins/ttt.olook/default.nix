# Olook: a mail client (stdlib Python + QML). HTML mail renders in
# QtWebEngine, which aborts inside Quickshell (argc 0) unless
# lib/argcshim.so is preloaded; Finish setup builds it with gcc and adds an
# LD_PRELOAD line to Hyprland's env. Pattern: the shim built with Nix (in
# the plugin's tree and preloaded into the shell's unit), and QtWebEngine
# for Quickshell's Qt.
{ lib, stdenv, fetchFromGitHub, omarchyUnstable, writeText, python3 }:
let
  src = fetchFromGitHub {
    owner = "TiniTinyTerminator";
    repo = "Olook";
    rev = "50b38afa34513d41dcd9881762edb1669671ed4d";
    hash = "sha256-BKCKeGnG3k8jMnbWY9SNzTCtx8MWMqo8Mn5RwjHXPjA=";
  };

  argcshim = stdenv.mkDerivation {
    pname = "olook-argcshim";
    version = "1.2.3-unstable-50b38af";
    inherit src;
    # It acts only in a process named quickshell; nixpkgs' is wrapped.
    postPatch = ''
      substituteInPlace lib/argcshim.c --replace-fail \
        'cached = strcmp(name, "quickshell") == 0;' \
        'cached = strcmp(name, "quickshell") == 0 || strcmp(name, ".quickshell-wrapped") == 0;'
    '';
    buildPhase = "$CC -shared -fPIC -O2 -o argcshim.so lib/argcshim.c -ldl";
    installPhase = "install -Dm755 argcshim.so $out/lib/argcshim.so";
  };
in
{
  inherit src;
  helpers."lib/argcshim.so" = "${argcshim}/lib/argcshim.so";
  qmlModules = [ omarchyUnstable.kdePackages.qtwebengine ];
  # Only the shell needs it (the shim does nothing in other processes).
  userServices."omarchy-shell.service.d/olook-argcshim.conf" = writeText "olook-argcshim.conf" ''
    [Service]
    Environment=LD_PRELOAD=${argcshim}/lib/argcshim.so
  '';
  packages = [ python3 ];
  meta.description = "Mail client (its QtWebEngine argc shim built and preloaded into the shell)";
}
