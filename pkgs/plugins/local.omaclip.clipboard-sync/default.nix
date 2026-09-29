# OmaClip: syncs the clipboard with an Android phone over adb. bin/omaclip
# execs bin/omaclip-rs, the Rust daemon upstream's bin/build compiles with
# cargo. Pattern: a helper inside the plugin's tree.
{ lib, fetchFromGitHub, rustPlatform, android-tools }:
let
  src = fetchFromGitHub {
    owner = "podkovyrin";
    repo = "omaclip";
    rev = "ff42616d611542e52e24fdef5893ff3f1e7eb46a";
    hash = "sha256-S2DYnLkG42xVn6HPkjNYdML3m5LRks746/sHT5uJDr8=";
  };

  omaclip = rustPlatform.buildRustPackage {
    pname = "omaclip";
    version = "0.1.2-unstable-ff42616";
    inherit src;
    cargoHash = "sha256-B1uZsRHCtzEwbKZONXWZ11qr4VwlAg34tkd/nrJ1DWk=";
    meta.mainProgram = "omaclip";
  };
in
{
  inherit src;
  helpers."bin/omaclip-rs" = lib.getExe omaclip;
  packages = [ android-tools ]; # adb
  meta.description = "Clipboard sync with Android (omaclip-rs built from source)";
}
