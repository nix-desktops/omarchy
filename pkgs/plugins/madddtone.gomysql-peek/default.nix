# GoMySQL Peek: a MySQL browser panel. DbPeek.qml runs
# ~/.local/bin/omysql-engine, the Go engine (engine/) that install.sh builds
# there. Its go.mod asks for Go 1.27, which only nixos-unstable has.
# Pattern: a link in the home.
{ lib, fetchFromGitHub, omarchyUnstable }:
let
  src = fetchFromGitHub {
    owner = "madddtone";
    repo = "omarchy-gomysql-peek";
    rev = "585bf67575280b56eff03d3b904cf430bebd2023";
    hash = "sha256-NlZunl+r8vnnSvFp5ExCWmaA/wcle4ZGKkx1xN0ZyB8=";
  };

  buildGoModule = omarchyUnstable.buildGoModule.override { go = omarchyUnstable.go_1_27; };
  engine = buildGoModule {
    pname = "omysql-engine";
    version = "0-unstable-585bf67";
    inherit src;
    modRoot = "engine";
    vendorHash = "sha256-0plc4gUFfI6T56SX2Rs5csUQKXQuDwPNJDrNbSTYqiQ=";
    env.CGO_ENABLED = 0;
    ldflags = [ "-s" "-w" ];
    postInstall = "mv $out/bin/engine $out/bin/omysql-engine";
    meta.mainProgram = "omysql-engine";
  };
in
{
  inherit src;
  home.".local/bin/omysql-engine" = lib.getExe engine;
  meta.description = "MySQL browser (omysql-engine built from engine/, linked at ~/.local/bin)";
}
