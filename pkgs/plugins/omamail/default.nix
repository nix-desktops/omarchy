# Omamail: all mail goes through the Rust backend (`omamail serve`), which
# scripts/backend-runtime.py downloads from GitHub releases into
# ~/.local/share/omamail/bin unless OMAMAIL_BIN names one. Pattern: the
# backend built from the repo, and OMAMAIL_BIN's default patched to it.
{ lib, fetchFromGitHub, rustPlatform }:
let
  src = fetchFromGitHub {
    owner = "huacnlee";
    repo = "omamail";
    rev = "2a5a26cf5559dee78291fc5e34876fc5dfd39959";
    hash = "sha256-3FSpciJNlq57twuhIyyOkxw7WmfH2pzh06DA+fuK6rA=";
  };

  omamail = rustPlatform.buildRustPackage {
    pname = "omamail";
    version = "0.10.7-unstable-2a5a26c";
    inherit src;
    cargoHash = "sha256-WT5Qv743d4cT7UZvF4Z7ZbRX/jymj1jCEglncrevBSw=";
    # Integration tests want mail servers and the network.
    doCheck = false;
    meta.mainProgram = "omamail";
  };
in
{
  inherit src;
  postPatch = ''
    substituteInPlace scripts/backend-runtime.py \
      --replace-fail 'os.environ.get("OMAMAIL_BIN", "")' 'os.environ.get("OMAMAIL_BIN", "${lib.getExe omamail}")'
  '';
  meta.description = "Mail client (the omamail backend built from the repo, OMAMAIL_BIN pointed at it)";
}
