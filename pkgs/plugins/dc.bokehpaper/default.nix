# Bokehpaper: a GL wallpaper (a Wayland layer-shell client in C). Service.qml
# runs bokehpaper-launch, which builds it with make into ~/.cache on first
# use and runs it from there. Built here, and the launcher pointed at it.
# Pattern: a build step at first run patched to a store path.
{ lib, stdenv, fetchFromGitHub, pkg-config, python3, wayland, wayland-scanner, libepoxy, libGL }:
let
  src = fetchFromGitHub {
    owner = "dobrician";
    repo = "omarchy-bokehpaper";
    rev = "5ed7206fbd932e3991fa4bb2a70a60ca10a8b97f";
    hash = "sha256-/ZHV4iiOeW3FP8jaIIi1ZCV7RCJqFAAVlj9SziybFlQ=";
  };

  bokehpaper = stdenv.mkDerivation {
    pname = "bokehpaper";
    version = "0-unstable-5ed7206";
    inherit src;
    nativeBuildInputs = [ pkg-config python3 wayland-scanner ];
    buildInputs = [ wayland libepoxy libGL ];
    buildFlags = [ "wallpaper" ];
    installPhase = "install -Dm755 build/bokehpaper $out/bin/bokehpaper";
    meta.mainProgram = "bokehpaper";
  };
in
{
  inherit src;
  postPatch = ''
    substituteInPlace bokehpaper-launch \
      --replace-fail 'build=$cache/$stamp' 'build=${bokehpaper}/bin'
  '';
  meta.description = "Bokeh wallpaper (the renderer built with its Makefile)";
}
