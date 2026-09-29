# OmaFrames: vines and a chameleon drawn by a Hyprland plugin
# (native/, hyprpm upstream); the bar widget toggles it. With no plugin
# path in its settings the widget assumes hyprpm; the default is pointed at
# the Nix-built plugin, which hyprland.lua also loads at login.
# Pattern: a Hyprland compositor plugin.
{ lib, fetchFromGitHub, mkHyprlandPlugin, pango, cairo, libinput, systemdLibs }:
let
  src = fetchFromGitHub {
    owner = "bitshaker";
    repo = "omaframes";
    rev = "f99224d79b8eb16e59006c3bbeeebf02c27a21b6";
    hash = "sha256-mbAiBHUtPlYZ7OhqB6j434ZbzSJtyx8HW5Elp8nMLJo=";
  };

  omaframes = mkHyprlandPlugin {
    pluginName = "omaframes";
    version = "0-unstable-f99224d";
    inherit src;
    sourceRoot = "${src.name}/native";
    buildInputs = [ pango cairo libinput systemdLibs ];
    installPhase = "install -Dm755 omaframes-native.so $out/lib/libomaframes.so";
    meta.description = "OmaFrames Hyprland plugin";
  };
in
{
  inherit src;
  hyprlandPlugins = [ omaframes ];
  postPatch = ''
    substituteInPlace shell/Service.qml \
      --replace-fail 'return configured' 'return configured || "${omaframes}/lib/libomaframes.so"'
  '';
  meta.description = "Vines and a chameleon on windows (the omaframes Hyprland plugin)";
}
