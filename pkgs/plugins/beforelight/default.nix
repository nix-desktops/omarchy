# Before Light: classic screensavers (SDL2 C programs, engine/) plus a
# layer-shell LD_PRELOAD shim (engine/overlay, SDL3). Service.qml runs
# scripts/setup.sh on enable, which compiles them into
# ~/.config/omarchy/branding/screensaver and ~/.config/omarchy/bin unless
# ~/.config/omarchy/beforelight.setup names this version and they're there;
# then it installs its launchers and PATH line. Pattern: the savers and the
# shim built with Nix, linked where setup.sh puts them, with its stamp.
{ lib, stdenv, fetchFromGitHub, writeText, pkg-config, wayland, wayland-scanner
, SDL2, SDL2_image, SDL2_ttf, SDL2_mixer, sdl3, python3 }:
let
  src = fetchFromGitHub {
    owner = "flynnsbit";
    repo = "omarchy-beforelight";
    rev = "b6a9bed32489664f70b533e09ff3016f021b9b8b";
    hash = "sha256-FJE174tqItyNYqhT9V4xE4U7RQN0RC/gNyJ0I9yG5RY=";
  };

  version = "1.0.1"; # manifest.json's: what the stamp holds
  savers = [ "bouncingball" "fadeout" "fishsaver" "globe" "hardrain" "lifeforms" "lifeforms_new"
    "logo" "matrix" "messages" "messages2" "paperfire" "rainstorm" "randomizer" "spotlight"
    "starrynight" "toastersaver" "warp" "worms" ];

  engine = stdenv.mkDerivation {
    pname = "beforelight";
    inherit version src;
    nativeBuildInputs = [ pkg-config wayland-scanner SDL2 ];
    buildInputs = [ SDL2 SDL2_image SDL2_ttf SDL2_mixer sdl3 wayland ];
    buildPhase = ''
      runHook preBuild
      make -C engine CC=cc BUILD=$PWD/out/savers all
      make -C engine/overlay CC=cc OUTDIR=$PWD/out/overlay
      runHook postBuild
    '';
    installPhase = ''
      mkdir -p $out
      cp -r out/savers $out/savers
      install -Dm755 out/overlay/libbeforelight-overlay.so $out/lib/libbeforelight-overlay.so
    '';
  };
in
{
  inherit src;
  home = lib.genAttrs' savers (s:
    lib.nameValuePair ".config/omarchy/branding/screensaver/${s}" "${engine}/savers/${s}")
  // {
    ".config/omarchy/bin/libbeforelight-overlay.so" = "${engine}/lib/libbeforelight-overlay.so";
    ".config/omarchy/beforelight.setup" = writeText "beforelight.setup" "${version}\n";
  };
  packages = [ python3 ];
  meta.description = "Classic screensavers (the SDL savers and layer-shell shim built with Nix)";
}
