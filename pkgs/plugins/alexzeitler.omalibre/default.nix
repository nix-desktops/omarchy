# Omalibre: a panel for omalibre, the Rust TUI ebook reader in the same
# repo. omalibre-run looks for omalibre on PATH (then ~/.local/bin, where
# its installer downloads a release). Pattern: the helper on PATH.
{ lib, fetchFromGitHub, rustPlatform }:
let
  src = fetchFromGitHub {
    owner = "AlexZeitler";
    repo = "omalibre";
    rev = "76d901258be26f645a695efd783b00bfaa3046fb";
    hash = "sha256-yo5bkUGGSZOJzQuTuBcQA6k3V4VOhhvHRAh+e/hLr0M=";
  };

  omalibre = rustPlatform.buildRustPackage {
    pname = "omalibre";
    version = "0.1.5-unstable-76d9012";
    inherit src;
    cargoHash = "sha256-sFGJQPuMggu7B7ZYVJsmqFOGlg4T13s0F0AtVtdmp1E=";
    # These make a private scratch dir in XDG_RUNTIME_DIR (else a shared
    # temp dir), which the sandbox doesn't give them.
    checkFlags = [
      "--skip=paths::tests::the_scratch_directory_admits_nobody_else"
      "--skip=tests::the_scratch_file_stays_private_and_never_outlives_the_edit"
    ];
    meta.mainProgram = "omalibre";
  };
in
{
  inherit src;
  packages = [ omalibre ];
  meta.description = "Ebook library panel (omalibre built from the repo, on PATH)";
}
