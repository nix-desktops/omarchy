# Theoria: a remote for the Theoria research engine (the `theoria` npm
# package). Engine.qml expects it in ~/.local/share/theoria/engine/
# node_modules (npm install from engine/package-lock.json) and runs node
# from /usr/bin. Pattern: node_modules built with Nix, linked in the home.
{ lib, fetchFromGitHub, buildNpmPackage, nodejs_24, curl }:
let
  src = fetchFromGitHub {
    owner = "broken-branch";
    repo = "omarchy-theoria";
    rev = "f4f5643a4831f327e2b8afb2b0ce4f3ef4fd3d30";
    hash = "sha256-K2oMlxqXMKW5YGuTIqiZKMNpULkZ77qi0rPwml7mjeQ=";
  };

  engine = buildNpmPackage {
    pname = "theoria-engine";
    version = "2.3.1";
    src = "${src}/engine";
    nodejs = nodejs_24;
    npmDepsHash = "sha256-iGCJcEMJkF9ChBVKhTy1ZDkTOj18l47d8PAAz0f5XuY=";
    npmFlags = [ "--ignore-scripts" ]; # as upstream installs it
    dontNpmBuild = true;
    installPhase = ''
      mkdir -p $out
      cp -r package.json package-lock.json node_modules $out/
    '';
  };
in
{
  inherit src;
  home.".local/share/theoria/engine" = engine;
  packages = [ nodejs_24 curl ];
  meta.description = "Theoria research engine remote (its npm engine built with Nix, linked in the home)";
}
