# Hyprworld: workspaces overview and layout. bootstrap.py, run at every
# shell start, compiles native/shared-workspaces.cpp (a Hyprland compositor
# plugin) with native/build.sh into ~/.cache/hyprworld/<key> and loads it
# with hyprctl. Built here against the desktop's Hyprland, and bootstrap
# pointed at it. Pattern: a Hyprland plugin the plugin loads itself, its
# build step patched to a store path.
{ lib, fetchFromGitHub, mkHyprlandPlugin }:
let
  src = fetchFromGitHub {
    owner = "tdemers218";
    repo = "hyprworld";
    rev = "539a3ae7342ae6baddeb52064da5317dd91266ee";
    hash = "sha256-GV8Mfs54Z2VvoIYFl3yABemvj5+oi73C5SPhdJ0blcI=";
  };

  shared-workspaces = mkHyprlandPlugin {
    pluginName = "shared-workspaces";
    version = "0-unstable-539a3ae";
    inherit src;
    sourceRoot = "${src.name}/native";
    # As native/build.sh does.
    buildPhase = ''
      $CXX -std=c++23 -shared -fPIC -O2 -Wall -Wextra $(pkg-config --cflags hyprland) \
        shared-workspaces.cpp -o shared-workspaces.so
    '';
    installPhase = "install -Dm755 shared-workspaces.so $out/lib/shared-workspaces.so";
    meta.description = "Hyprworld's shared workspaces for Hyprland";
  };
in
{
  inherit src;
  postPatch = ''
    substituteInPlace bootstrap.py \
      --replace-fail "subprocess.run(['timeout', '--kill-after=5s', '120s', 'bash', str(root / 'native/build.sh'), str(cache)], check=True, timeout=130)" \
                     "cache = Path('${shared-workspaces}/lib')  # Nix-built"
  '';
  meta.description = "Workspaces overview (its Hyprland plugin built from native/)";
}
