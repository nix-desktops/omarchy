# Cece: a cat chasing the cursor. The widget starts and stops the `cece`
# command (its setting, default "cece" on PATH), a Rust Wayland overlay that
# install.sh builds into ~/.local/bin. Pattern: a package on PATH.
{ lib, fetchFromGitHub, rustPlatform, pkg-config, alsa-lib }:
let
  src = fetchFromGitHub {
    owner = "ure";
    repo = "cece";
    rev = "0d458ec32207398da248ebedf2cddd5198453801";
    hash = "sha256-gmAqUgKkE5nkbQc5R8zS8l436iPQoi9W5/AmzgjQTL0=";
  };

  cece = rustPlatform.buildRustPackage {
    pname = "cece";
    version = "0.2.0-unstable-0d458ec";
    inherit src;
    cargoHash = "sha256-TC0hPbOF+UnyGtdIeETHGSP8PdbjoSbkWoeKgWp7L7c=";
    nativeBuildInputs = [ pkg-config ];
    buildInputs = [ alsa-lib ]; # its sounds (rodio → cpal → ALSA)
    meta.mainProgram = "cece";
  };
in
{
  inherit src;
  packages = [ cece ];
  meta.description = "Desktop cat (cece built from the repo, on PATH)";
}
