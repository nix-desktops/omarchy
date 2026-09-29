# Aura Blur: a gradual blur behind the shell's popups. A Hyprland plugin
# (compositor/) draws it, fed by a C++ QML module (observer/,
# `import GradualBlurObserver`) reporting popup geometry over a socket;
# setup.sh builds both, adds the plugin dir to QML_IMPORT_PATH and loads the
# .so with hyprctl from ~/.config/hypr. Pattern: a compositor plugin plus a
# QML module, its Hyprland settings as hyprlandConfig.
{ fetchFromGitHub, omarchyUnstable, mkHyprlandPlugin }:
let
  src = fetchFromGitHub {
    owner = "Sh3nron";
    repo = "omarchy-aura-blur";
    rev = "bc71c1b40fa920861e4a4802687c7f88bd6d07de";
    hash = "sha256-A0yKaLk+xVUB6YPwYLqiKo2NyxquOEC8lwH2ZRs+LOI=";
  };
  inherit (omarchyUnstable) stdenv cmake ninja pkg-config json_c qt6;

  blur = mkHyprlandPlugin {
    pluginName = "gradual-blur-plugin";
    version = "1.0.1-unstable-bc71c1b";
    inherit src;
    sourceRoot = "${src.name}/compositor";
    nativeBuildInputs = [ cmake pkg-config ];
    buildInputs = [ json_c ];
    installPhase = "install -Dm755 gradual-blur-plugin.so $out/lib/libgradual-blur-plugin.so";
    meta.description = "Aura Blur's compositor plugin";
  };

  observer = stdenv.mkDerivation {
    pname = "gradual-blur-observer";
    version = "1.0.1-unstable-bc71c1b";
    inherit src;
    sourceRoot = "${src.name}/observer";
    nativeBuildInputs = [ cmake ninja ];
    buildInputs = [ qt6.qtbase qt6.qtdeclarative ];
    dontWrapQtApps = true;
    installPhase = ''
      dir=$out/lib/qt-6/qml/GradualBlurObserver
      install -Dm644 ../plugin/GradualBlurObserver/qmldir $dir/qmldir
      install -Dm755 native/libgradualblurobserverplugin.so $dir/libgradualblurobserverplugin.so
    '';
  };
in
{
  inherit src;
  hyprlandPlugins = [ blur ];
  qmlModules = [ observer ];
  # copy/gradual-blur.lua without its load-plugin step (the plugin is
  # loaded by the generated hyprland.lua).
  hyprlandConfig = ''
    hl.config({ decoration = { blur = { enabled = true, size = 6, passes = 3, noise = 0.0,
      brightness = 1.0, contrast = 1.0, vibrancy = 0.0, new_optimizations = true } } })
    o.window(".*", { no_blur = true })
  '';
  # Read by both halves.
  home.".config/hypr/gradual-blur/config.jsonc" = "${src}/copy/config.jsonc";
  meta.description = "Gradual blur behind shell popups (a Hyprland plugin and a QML module built from source)";
}
