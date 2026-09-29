# Bookmarks: the QML runs worker-launcher.sh, which has worker_setup.py
# exec a worker it downloaded (or built with cargo) into XDG_DATA_HOME,
# checked against a record. Needs Rust 1.96: nixos-unstable's toolchain.
# Pattern: the launcher patched to exec the Nix-built worker.
{ lib, fetchFromGitHub, omarchyUnstable }:
let
  src = fetchFromGitHub {
    owner = "StefanMarAntonsson";
    repo = "omarchy-bookmarks";
    rev = "139f6fe1c5d2a4bb2a53e537f591fdf56b2958db";
    hash = "sha256-XY3SDdFRBkuZMYgZmtIe/qSp4FqcAL9oLdSlopxipq8=";
  };

  worker = omarchyUnstable.rustPlatform.buildRustPackage {
    pname = "omarchy-bookmarks-worker";
    version = "2.0.1-unstable-139f6fe";
    inherit src;
    cargoHash = "sha256-bAjVDJT6QbydwDGpaMiFXUPtKv746mwsgOf8Y/d4OY0=";
    meta.mainProgram = "omarchy-bookmarks-worker";
  };
in
{
  inherit src;
  postPatch = ''
    substituteInPlace worker-launcher.sh \
      --replace-fail 'exec python3 -I -B "$plugin_dir/scripts/worker_setup.py" launch' \
                     'exec ${lib.getExe worker}'
  '';
  meta.description = "Bookmarks library (omarchy-bookmarks-worker built from the repo)";
}
