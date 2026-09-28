# Screen Arrangement: a monitor layout canvas whose backend, the Rust CLI
# omarchy-screen-menu (the repo's crate), it runs from PATH (upstream copies
# it to ~/.local/bin). Pattern: a helper on PATH.
{ lib, fetchFromGitHub, rustPlatform }:
let
  src = fetchFromGitHub {
    owner = "jorisvilardell";
    repo = "omarchy-screen-arrangement";
    rev = "82593911cd028a6ef5d72fa7f22c7e0255bab78d";
    hash = "sha256-Mmw5p4KGAawlGEtLm+PYd5H+kNI9J7Yf+gm0S47CvLs=";
  };

  omarchy-screen-menu = rustPlatform.buildRustPackage {
    pname = "omarchy-screen-menu";
    version = "0.1.0-unstable-8259391";
    inherit src;
    cargoHash = "sha256-coy77o193mpbl/D+tX6ZLvkj3R61zuJVBAE5yVQAIQM=";
    meta.mainProgram = "omarchy-screen-menu";
  };
in
{
  inherit src;
  packages = [ omarchy-screen-menu ];
  meta.description = "Monitor arrangement (omarchy-screen-menu built from source, on PATH)";
}
