# Omavault: gocryptfs vaults; Service.qml runs <plugin>/omavault-helper (Rust:
# scan, mount, unmount), which install.sh cargo-builds or setup-helper.sh
# downloads. Pattern: a helper inside the plugin's tree.
{ lib, fetchFromGitHub, rustPlatform, gocryptfs, util-linux }:
let
  src = fetchFromGitHub {
    owner = "skvggor";
    repo = "omavault-plugin";
    rev = "654640090e26d6f3ec90925c5a908e3998b30eef";
    hash = "sha256-4Vb18DGWb6t/4YCeWFjIvdxQcLIU8oJsm6Eu1Z9vMxE=";
  };

  helper = rustPlatform.buildRustPackage {
    pname = "omavault-helper";
    version = "0.3.1-unstable-6546400";
    inherit src;
    cargoHash = "sha256-aUwjTqm9lMHwCLxoTpYzCLgESA8mO1BpQnw7rtlULFk=";
    # Vault creation runs gocryptfs under util-linux `script` (a pty).
    nativeCheckInputs = [ util-linux ];
    meta.mainProgram = "omavault-helper";
  };
in
{
  inherit src;
  helpers."omavault-helper" = lib.getExe helper;
  # fusermount3 is NixOS's setuid wrapper (programs.fuse, on by default).
  packages = [ gocryptfs util-linux ];
  meta.description = "gocryptfs vaults (omavault-helper built from the repo)";
}
