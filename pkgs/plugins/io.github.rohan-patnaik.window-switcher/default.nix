# Orbit: an Alt+Tab window switcher and snap layouts (QML over Hyprland IPC),
# wired up by the plugin's bindings.lua, which the README has you dofile from
# ~/.config/hypr/bindings.lua. Its optional native bridge (native/, a
# Hyprland plugin: live snap drags, surface readiness) is built by hand and
# `hyprctl plugin load`-ed. Pattern: a Hyprland plugin, plus the Lua it
# asks for.
{ lib, fetchFromGitHub, mkHyprlandPlugin, jq }:
let
  src = fetchFromGitHub {
    owner = "rohan-patnaik";
    repo = "orbit";
    rev = "b9115759175be41b71516926037b480f92449e8f";
    hash = "sha256-bpUxVu2fFWk4AcaP55EVRuatBI99QRjQDWQuAdE2mRc=";
  };

  orbit-drag = mkHyprlandPlugin {
    pluginName = "orbit-drag";
    version = "0-unstable-b911575";
    inherit src;
    sourceRoot = "${src.name}/native";
    buildPhase = "make CXX=g++";
    installPhase = "install -Dm755 orbit-drag.so $out/lib/liborbit-drag.so";
    meta.description = "Orbit's native Hyprland bridge";
  };
in
{
  inherit src;
  hyprlandPlugins = [ orbit-drag ];
  # The README's guarded include.
  hyprlandConfig = ''
    local orbit_bindings = os.getenv("HOME") .. "/.config/omarchy/plugins/io.github.rohan-patnaik.window-switcher/bindings.lua"
    local orbit_file = io.open(orbit_bindings, "r")
    if orbit_file then
      orbit_file:close()
      dofile(orbit_bindings)
    end
  '';
  packages = [ jq ];
  meta.description = "Window switcher (its Hyprland bridge built against the desktop's Hyprland, bindings loaded)";
}
