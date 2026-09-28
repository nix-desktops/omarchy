# OmaStats: system stats. sampler.py execs <plugin>/bin/omastats-sampler
# (a prebuilt glibc binary upstream) and falls back to Python when it
# can't. Pattern: a helper inside the plugin's tree, built from sampler/.
{ lib, fetchFromGitHub, rustPlatform }:
let
  src = fetchFromGitHub {
    owner = "crmne";
    repo = "omastats";
    rev = "61878e8ecef620e707b112f6d56f6434282827ac";
    hash = "sha256-Oo++iHKXhfBQgy85t1iVF10UJLU+3fjgNI60lvO50AQ=";
  };

  sampler = rustPlatform.buildRustPackage {
    pname = "omastats-sampler";
    version = "1.4.0-unstable-61878e8";
    inherit src;
    sourceRoot = "${src.name}/sampler";
    cargoHash = "sha256-A757nb+rJT8B0yOQOhIIkWIJXZrAqSswuzHJGd2hZz0=";
    meta.mainProgram = "omastats-sampler";
  };
in
{
  inherit src;
  helpers."bin/omastats-sampler" = lib.getExe sampler;
  meta.description = "System stats (omastats-sampler built from sampler/)";
}
