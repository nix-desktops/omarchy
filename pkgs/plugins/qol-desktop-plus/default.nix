# QoL Desktop+: a taskbar and switcher (taskbar.py). Its optional Hyprland
# plugin (native/minimize.cpp) honours apps' minimize requests; taskbar.py
# builds it with native/build.sh into ~/.local/state (next to a
# helper-path file the plugin reads) once /usr/include/hyprland matches the
# running Hyprland, and loads it. Pattern: the Hyprland plugin built by
# Nix; build.sh replaced by one that installs it, the header check pointed
# at the Hyprland it was built against, libxkbcommon at the store.
{ lib, fetchFromGitHub, mkHyprlandPlugin, hyprland, writeShellScript, coreutils, libxkbcommon }:
let
  src = fetchFromGitHub {
    owner = "xxsteven69xx";
    repo = "qol-desktop-plus";
    rev = "928f44fe40741fd832f1395af872b1ac60b33782";
    hash = "sha256-HKqTYjlDecfTobQr3NeU9lR4ALr1Xl1e+tzt12xwAlE=";
  };

  minimize = mkHyprlandPlugin {
    pluginName = "omarchy-taskbar-minimize";
    version = "1.3.0-unstable-928f44f";
    inherit src;
    sourceRoot = "${src.name}/native";
    buildPhase = ''
      runHook preBuild
      $CXX -std=c++26 -O2 -shared -fPIC -fno-gnu-unique \
        $(pkg-config --cflags hyprland aquamarine hyprlang pixman-1 libdrm) minimize.cpp -o minimize.so
      runHook postBuild
    '';
    installPhase = "install -Dm755 minimize.so $out/lib/libomarchy-taskbar-minimize.so";
    meta.description = "QoL Desktop+ minimize Hyprland plugin";
  };

  # native/build.sh [OUTPUT]: the .so at OUTPUT, helper-path beside it.
  build = writeShellScript "build.sh" ''
    set -eu
    PATH=${coreutils}/bin
    cd -- "$(dirname -- "$0")"
    output=''${1:-''${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/taskbar/native/manual/minimize.so}
    mkdir -p -- "$(dirname -- "$output")"
    install -m755 ${minimize}/lib/libomarchy-taskbar-minimize.so "$output.new"
    realpath ../taskbar.py | tr -d '\n' > "$(dirname -- "$output")/helper-path"
    mv -- "$output.new" "$output"
  '';
in
{
  inherit src;
  helpers."native/build.sh" = build;
  postPatch = ''
    # ctypes.util.find_library finds nothing on NixOS.
    substituteInPlace settings.py \
      --replace-fail "ctypes.util.find_library('xkbcommon')" "'${libxkbcommon}/lib/libxkbcommon.so.0'"
    substituteInPlace taskbar.py \
      --replace-fail "Path('/usr/include/hyprland/src/version.h')" "Path('${hyprland.dev}/include/hyprland/src/version.h')"
  '';
  meta.description = "Taskbar and switcher (its minimize Hyprland plugin built by Nix)";
}
