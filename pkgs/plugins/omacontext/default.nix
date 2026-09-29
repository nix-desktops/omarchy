# OmaContext: workspace contexts through its bash CLI and hyprctl; the
# optional Hyprland plugin (main.cpp, built with make against
# /usr/include/hyprland upstream) adds native dispatchers.
# Pattern: a Hyprland compositor plugin.
{ lib, fetchFromGitHub, mkHyprlandPlugin }:
let
  src = fetchFromGitHub {
    owner = "SenPaiOfUrSenSei";
    repo = "omacontext";
    rev = "92ab1ec6251e96b1c177f3140d58993088ef56f1";
    hash = "sha256-CPSnlGpn9eZBJm+9A9D/TjllDgJNZt8aRHTA8vkpvUo=";
  };

  omacontext = mkHyprlandPlugin {
    pluginName = "omacontext";
    version = "0-unstable-92ab1ec";
    inherit src;
    buildPhase = ''
      runHook preBuild
      $CXX -shared -fPIC -O2 -std=c++23 main.cpp -o omacontext.so \
        $(pkg-config --cflags hyprland pixman-1 libdrm hyprlang)
      runHook postBuild
    '';
    installPhase = "install -Dm755 omacontext.so $out/lib/libomacontext.so";
    meta.description = "OmaContext Hyprland plugin";
  };
in
{
  inherit src;
  hyprlandPlugins = [ omacontext ];
  meta.description = "Workspace contexts (with its Hyprland plugin for native dispatchers)";
}
