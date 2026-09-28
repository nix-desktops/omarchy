# World Clock: a 3D Earth wallpaper. Service.qml runs bin/world-clock, which
# make-s the C renderer (EGL/GLES2, layer shell) into ~/.cache on first run
# (the Makefile reads /usr/share/wayland-protocols) and starts it through
# tools/wallpaper.py. Pattern: the renderer built with Nix, the launcher
# patched to it.
{ lib, stdenv, fetchFromGitHub, pkg-config, wayland, wayland-scanner, wayland-protocols
, libGL, libpng, glib, python3, libnotify, jq }:
let
  src = fetchFromGitHub {
    owner = "spaceXrace";
    repo = "omarchy-world-clock";
    rev = "0b31c67684dc65be4816a71bce414a54ea2677f4";
    hash = "sha256-xsj0Jyq5m2e2BRgArkAf/SPCblcrb68Zn6t9ZSMAu80=";
  };

  cities-earth = stdenv.mkDerivation {
    pname = "cities-earth";
    version = "0-unstable-0b31c67";
    inherit src;
    nativeBuildInputs = [ pkg-config wayland-scanner ];
    buildInputs = [ wayland libGL libpng glib ];
    postPatch = ''
      substituteInPlace Makefile \
        --replace-fail /usr/share/wayland-protocols ${wayland-protocols}/share/wayland-protocols
    '';
    installPhase = "install -Dm755 build/cities-earth $out/bin/cities-earth";
    meta.mainProgram = "cities-earth";
  };
in
{
  inherit src;
  postPatch = ''
    substituteInPlace bin/world-clock \
      --replace-fail 'binary=$cache_root/build/cities-earth' 'binary=${lib.getExe cities-earth}'
  '';
  packages = [ python3 libnotify jq ];
  meta.description = "3D Earth world-clock wallpaper (its renderer built with Nix)";
}
