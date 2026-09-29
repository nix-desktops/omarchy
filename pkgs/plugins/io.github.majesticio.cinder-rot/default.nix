# Cinder Rot: a fire effect that is a Hyprland compositor plugin (plugin/,
# C++23); the bar widget drives it with hyprctl dispatchers and loads
# ~/.local/lib/hyprland/plugins/cinder-rot.so (`make install`) when
# Hyprland doesn't know them. Pattern: a Hyprland plugin, also linked where
# the widget loads it from.
{ lib, fetchFromGitHub, mkHyprlandPlugin, libGL }:
let
  src = fetchFromGitHub {
    owner = "majesticio";
    repo = "cinder-rot";
    rev = "a7bc9a053a33836e029a760ff1a0892aad737ba2";
    hash = "sha256-gY1BjBWPh+d+GKT3E5XQ0Zk0+Mrd+qfj53U2rCqmAlY=";
  };

  cinder-rot = mkHyprlandPlugin {
    pluginName = "cinder-rot";
    version = "1.3.7-unstable-a7bc9a0";
    inherit src;
    sourceRoot = "${src.name}/plugin";
    buildInputs = [ libGL ];
    installPhase = "install -Dm755 cinder-rot.so $out/lib/libcinder-rot.so";
    meta.description = "Cinder Rot fire effect for Hyprland";
  };
in
{
  inherit src;
  hyprlandPlugins = [ cinder-rot ];
  home.".local/lib/hyprland/plugins/cinder-rot.so" = "${cinder-rot}/lib/libcinder-rot.so";
  meta.description = "Fire effect (its Hyprland plugin built from plugin/)";
}
