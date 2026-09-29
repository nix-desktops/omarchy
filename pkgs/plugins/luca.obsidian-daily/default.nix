# Obsidian daily notes: BarWidget.qml runs <plugin>/omarchy/bin/obsidian-daily-qs-<arch>,
# committed static musl builds. Pattern: the helper rebuilt from the
# repo's Rust source, in the tree.
{ lib, stdenv, fetchFromGitHub, omarchyUnstable, xdg-utils }:
let
  src = fetchFromGitHub {
    owner = "LucaNerlich";
    repo = "obsidian-daily-qs";
    rev = "5125055128d2b9cd30bb6957a094a4f1fc1471a5";
    hash = "sha256-QHj1+KfP3d/KuaRUhMaRhgzHYa1RPOQLqe+pOAhITeY=";
  };
  # Cargo.toml's rust-version is 1.98.1, newer than 26.05's rustc.
  backend = omarchyUnstable.rustPlatform.buildRustPackage {
    pname = "obsidian-daily-qs";
    version = "0-unstable-5125055";
    inherit src;
    cargoHash = "sha256-qfTLkvM+1OFuJ84vbSCALsRuTE0f0Vxp7E1VOC9lgJo=";
    # The tests keep undo files in ~/.cache.
    preCheck = "export HOME=$TMPDIR";
    # Its fake xdg-open runs /bin/sleep and /usr/bin/touch, which the sandbox lacks.
    checkFlags = [ "--skip=open_returns_while_desktop_handler_is_still_running" ];
    meta.mainProgram = "obsidian-daily-qs";
  };
in
{
  inherit src;
  helpers."omarchy/bin/obsidian-daily-qs-${stdenv.hostPlatform.uname.processor}" = lib.getExe backend;
  packages = [ xdg-utils ];
  meta.description = "Obsidian daily notes (obsidian-daily-qs built with Cargo)";
}
