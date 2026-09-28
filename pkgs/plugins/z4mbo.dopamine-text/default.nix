# Dopamine Text: typing effects at the caret. Service.qml runs bridge.py
# and audio.py with /usr/bin/python (AT-SPI through gi; audio.py dlopens
# libpulse-simple). bridge.py compiles native/caret.cpp (a Hyprland plugin
# for a precise caret) into ~/.cache when /usr/include/hyprland matches
# the running Hyprland, and loads it. Pattern: a Python env with the
# typelibs and libraries in a wrapper the QML runs, the AT-SPI bus's
# activation files in the home, and the Hyprland plugin
# built by Nix, loaded by the bridge from the store.
{ lib, fetchFromGitHub, mkHyprlandPlugin, hyprland, writeShellScript, python3, gobject-introspection, at-spi2-core, glib, libpulseaudio, lua5_4 }:
let
  src = fetchFromGitHub {
    owner = "z4mbo";
    repo = "dopamine-text";
    rev = "e8f39c3fe287f49bf3d10fe093213d3aa88037fd";
    hash = "sha256-OYGwBbyT2B2NqodUGE9Z9ohgI6huG1akG1Or6yrq1Zc=";
  };

  caret = mkHyprlandPlugin {
    pluginName = "dopamine-caret";
    version = "0-unstable-e8f39c3";
    inherit src;
    sourceRoot = "${src.name}/native";
    buildInputs = [ lua5_4 ];
    buildPhase = ''
      runHook preBuild
      $CXX -std=c++23 -shared -fPIC $(pkg-config --cflags hyprland lua) caret.cpp -o caret.so
      runHook postBuild
    '';
    installPhase = "install -Dm755 caret.so $out/lib/libdopamine-caret.so";
    meta.description = "Dopamine Text caret Hyprland plugin";
  };

  env = python3.withPackages (ps: [ ps.pygobject3 ]);
  python = writeShellScript "python" ''
    export GI_TYPELIB_PATH=${lib.makeSearchPath "lib/girepository-1.0" [ at-spi2-core glib gobject-introspection ]}''${GI_TYPELIB_PATH:+:$GI_TYPELIB_PATH}
    export LD_LIBRARY_PATH=${lib.makeLibraryPath [ libpulseaudio ]}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
    exec ${env}/bin/python "$@"
  '';
in
{
  inherit src;
  helpers."bin/python" = python;
  # AT-SPI needs its accessibility bus (a system setting on NixOS,
  # services.gnome.at-spi2-core): the D-Bus activation file and its unit.
  home = {
    ".local/share/dbus-1/services/org.a11y.Bus.service" = "${at-spi2-core}/share/dbus-1/services/org.a11y.Bus.service";
    ".config/systemd/user/at-spi-dbus-bus.service" = "${at-spi2-core}/lib/systemd/user/at-spi-dbus-bus.service";
  };
  postPatch = ''
    substituteInPlace Service.qml \
      --replace-fail '"/usr/bin/python"' 'decodeURIComponent(Qt.resolvedUrl("bin/python").toString().replace("file://",""))'
    substituteInPlace bridge.py \
      --replace-fail "Path('/usr/include/hyprland/src/version.h')" "Path('${hyprland.dev}/include/hyprland/src/version.h')" \
      --replace-fail "binary = cache / ('caret-' + version + '-' + digest + '.so')" "binary = Path('${caret}/lib/libdopamine-caret.so')"
  '';
  meta.description = "Typing effects (Python with AT-SPI, and its caret Hyprland plugin built by Nix)";
}
