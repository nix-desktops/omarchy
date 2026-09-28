# Omaswipe: per-workspace themes that follow 3-finger swipes. Its setup
# (assets.py) compiles a Hyprland plugin (hypr-plugin/) with g++ into
# ~/.config/hypr/plugins and loads it with hyprctl. Pattern: a Hyprland
# plugin loaded by hyprland.lua, with setup's compile and load patched out
# (it finds hyprland.lua already loads omaswipe-ws-offset).
{ lib, fetchFromGitHub, mkHyprlandPlugin }:
let
  src = fetchFromGitHub {
    owner = "LessUnderRated";
    repo = "OmaSwipe";
    rev = "4741343294e9f57a5148a8e55c6cd6af638c4628";
    hash = "sha256-c7b5Rzpm1mDZnFWr7slzM7AB4OHXx5kZOmmzuhLgZvU=";
  };

  offset = mkHyprlandPlugin {
    pluginName = "omaswipe-ws-offset";
    version = "0.8-unstable-4741343";
    inherit src;
    sourceRoot = "${src.name}/hypr-plugin";
    buildPhase = ''
      runHook preBuild
      $CXX -shared -fPIC -std=c++23 -O2 -DWLR_USE_UNSTABLE \
        $(pkg-config --cflags hyprland pixman-1 libdrm hyprutils) \
        -o omaswipe-ws-offset.so main.cpp
      runHook postBuild
    '';
    installPhase = "install -Dm755 omaswipe-ws-offset.so $out/lib/libomaswipe-ws-offset.so";
    meta.description = "Omaswipe workspace offset Hyprland plugin";
  };
in
{
  inherit src;
  hyprlandPlugins = [ offset ];
  # What setup's snippet adds besides loading the plugin.
  hyprlandConfig = ''
    hl.layer_rule({ match = { namespace = "omarchy-background" }, order = 0 })
    hl.layer_rule({ match = { namespace = "omaswipe-wallpaper" }, no_anim = true, animation = "none", order = 100 })
  '';
  postPatch = ''
    substituteInPlace assets.py \
      --replace-fail 'def compile_hypr_plugin():' 'def compile_hypr_plugin():
        return True


    def compile_hypr_plugin_upstream():' \
      --replace-fail 'def load_hypr_plugin():' 'def load_hypr_plugin():
        return True


    def load_hypr_plugin_upstream():'
  '';
  meta.description = "Workspace themes that follow swipes (the omaswipe-ws-offset Hyprland plugin)";
}
