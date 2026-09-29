# Muqun: SSH and agent sessions; the QML is the UI of a TypeScript sidecar
# (backend/) that scripts/run-sidecar.sh runs with bun from /usr/bin/bun (or
# ~/.bun), needing its dependencies installed (`bun install`, which nothing
# runs). Installed here from bun.lock next to a copy of backend/, which the
# launcher runs. Pattern: an install step patched to a store path, and bun
# on PATH (/usr/bin/bun through envfs).
{ lib, stdenvNoCC, runCommand, fetchFromGitHub, omarchyUnstable }:
let
  # bun.lock's format 2 needs bun 1.4 (nixos-unstable's).
  inherit (omarchyUnstable) bun;
  src = fetchFromGitHub {
    owner = "ryuhzk";
    repo = "omarchy-muqun";
    rev = "1e79a5268b5da0710dc38eee142531449506f0bd";
    hash = "sha256-niAaRNEIMA8Cv1ipJ8uKF2bO/sFHQOxBdOO8yKFxdYg=";
  };

  # A fixed-output derivation: bun fetches what bun.lock pins (7 packages,
  # all JavaScript).
  node_modules = stdenvNoCC.mkDerivation {
    pname = "omarchy-muqun-node-modules";
    version = "0.1.0-unstable-1e79a52";
    inherit src;
    nativeBuildInputs = [ bun ];
    impureEnvVars = lib.fetchers.proxyImpureEnvVars;
    dontConfigure = true;
    buildPhase = ''
      export HOME=$TMPDIR
      bun install --frozen-lockfile --production --ignore-scripts --no-progress --backend=copyfile
    '';
    installPhase = ''
      rm -rf node_modules/.bin node_modules/.cache
      cp -r node_modules $out
    '';
    dontFixup = true;
    outputHash = "sha256-P2SSvisfB9twc1tmOlx4dw+ow91fYbLAvn97ksOu+rA=";
    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
  };
  sidecar = runCommand "omarchy-muqun-sidecar" { } ''
    mkdir $out
    cp -r ${src}/backend ${src}/package.json $out/
    cp -r ${node_modules} $out/node_modules
  '';
in
{
  inherit src;
  postPatch = ''
    substituteInPlace scripts/run-sidecar.sh \
      --replace-fail '"$PLUGIN_DIR/backend/interface/main.ts"' '"${sidecar}/backend/interface/main.ts"'
  '';
  packages = [ bun ];
  meta.description = "SSH and agent sessions (its sidecar's dependencies from bun.lock, bun)";
}
