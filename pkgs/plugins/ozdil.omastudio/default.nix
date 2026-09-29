# OmaStudio: a RAW photo editor in its own Quickshell window. The bar
# widget runs `omastudio-dashboard` from PATH (Arch installs it with a
# PKGBUILD); the editor runs ~/.local/bin/omastudio-engine (Rust + LibRaw).
# Pattern: the PKGBUILD's layout as a package, plus a link in the home.
{ lib, fetchFromGitHub, rustPlatform, pkg-config, libraw, zenity }:
let
  src = fetchFromGitHub {
    owner = "ozdil";
    repo = "omarchy-omastudio";
    rev = "d979da2b4997de445c14995f6ada504150d69e3c";
    hash = "sha256-DfT9eNLVLZb3vfDk+aX+NRvXZfGozJP9Gji/mbAO2ck=";
  };
  omastudio = rustPlatform.buildRustPackage {
    pname = "omastudio";
    version = "0-unstable-d979da2";
    inherit src;
    cargoHash = "sha256-dfk5gitI1+mvQkBrX3YlGtsyFCEWncZHc36hdB4TqiU=";
    nativeBuildInputs = [ pkg-config ];
    buildInputs = [ libraw ];
    # A test writes to the Google Drive cache in ~/.cache.
    preCheck = "export HOME=$TMPDIR";
    # The launchers find qml/ next to themselves (realpath).
    postInstall = ''
      mkdir -p $out/share/omastudio
      cp -r qml omastudio omastudio-dashboard omastudio-status manifest.json $out/share/omastudio/
      for b in omastudio omastudio-dashboard omastudio-status; do
        ln -s $out/share/omastudio/$b $out/bin/$b
      done
      install -Dm644 omastudio.desktop -t $out/share/applications
    '';
    meta.mainProgram = "omastudio-engine";
  };
in
{
  inherit src;
  home.".local/bin/omastudio-engine" = lib.getExe omastudio;
  packages = [ omastudio zenity ];
  meta.description = "RAW photo editor (omastudio-engine built with Cargo; its launchers on PATH)";
}
