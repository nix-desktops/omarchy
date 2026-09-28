# Omarchy Keyguide: a shortcut HUD shown while a modifier is held. As a
# plugin, Service.qml runs scripts/plugin-bootstrap.sh, which compiles
# <plugin>/build/keyguide-observer with cc (behind a stamp of `cc
# --version`), then runs it. The observer reads /dev/input: the user needs
# access to the input devices (upstream's udev uaccess rule,
# packaging/70-omarchy-keyguide.rules, or the input group), which is a
# system setting. Pattern: a helper inside the plugin's tree, the bootstrap
# patched to use it.
{ lib, fetchFromGitHub, stdenv }:
let
  src = fetchFromGitHub {
    owner = "mrai125kr";
    repo = "omarchy-keyguide";
    rev = "048d3bb55a0a3770f967f9b1ecd6791751eb6708";
    hash = "sha256-DHNRWf91VOM38KkOu11AK9R+5YwHSJo1Pnj6V1tB86Y=";
  };

  observer = stdenv.mkDerivation {
    pname = "keyguide-observer";
    version = "0.1.1-unstable-048d3bb";
    inherit src;
    buildFlags = [ "build/keyguide-observer" ];
    installPhase = "install -Dm755 build/keyguide-observer $out/bin/keyguide-observer";
    meta.mainProgram = "keyguide-observer";
  };
in
{
  inherit src;
  helpers."build/keyguide-observer" = lib.getExe observer;
  postPatch = ''
    substituteInPlace scripts/plugin-bootstrap.sh \
      --replace-fail 'umask 077' 'exit 0 # build/keyguide-observer is Nix-built'
  '';
  meta.description = "Shortcut HUD (keyguide-observer built from src/observer; needs input device access)";
}
