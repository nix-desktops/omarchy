# Duo Hinge: a hinge effect for dual-screen laptops, a Hyprland compositor
# plugin (native/). runner.py compiles it with g++ against the installed
# Hyprland headers into a cache, checks it, loads it with hyprctl and
# unloads it when the service stops. Built here against the desktop's
# Hyprland, and the runner given the built plugin. Pattern: a Hyprland
# plugin the plugin loads itself, its build step patched to a store path.
{ lib, fetchFromGitHub, mkHyprlandPlugin, pixman, libdrm, libGL }:
let
  src = fetchFromGitHub {
    owner = "BrunooMoniz";
    repo = "omarchy-duo-hinge";
    rev = "0ca466cb47968983df8fac11e4216c4690f56c8d";
    hash = "sha256-IkmumGiRY3CTMp4LUl5IFit9UNJgFiXQJFrZizbSn2U=";
  };

  duo-hinge = mkHyprlandPlugin {
    pluginName = "duo-hinge";
    version = "0-unstable-0ca466c";
    inherit src;
    sourceRoot = "${src.name}/native";
    buildInputs = [ pixman libdrm libGL ];
    makeFlags = [ "BUILD=build" ];
    installPhase = "install -Dm755 build/duo-hinge.so $out/lib/duo-hinge.so";
    meta.description = "Duo Hinge effect for Hyprland";
  };
in
{
  inherit src;
  # The runner's build returns the cached plugin after checking it's the
  # user's own file with a build.json; the store's is used as is.
  postPatch = ''
    substituteInPlace runner.py \
      --replace-fail 'self.plugin, key = self.build(abi)' \
                     'self.plugin, key = Path("${duo-hinge}/lib/duo-hinge.so"), None  # Nix-built' \
      --replace-fail 'self.verify_binary(self.plugin.parent, key, abi)' 'None'
  '';
  meta.description = "Dual-screen hinge effect (its Hyprland plugin built from native/)";
}
