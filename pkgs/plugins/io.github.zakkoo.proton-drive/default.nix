# Proton Drive Sync: two-way sync with Proton Drive. The widget runs
# ~/.local/bin/proton-drive-sync (and accepts it only with install-engine's
# marker lines), which scripts/install-engine creates after `npm ci` and an
# esbuild bundle in ~/.local/share. Pattern: the engine built with
# buildNpmPackage, its launcher linked in the home. `proton-drive-sync
# login` once; `run` (or the panel) syncs.
{ lib, stdenv, fetchFromGitHub, buildNpmPackage, writeScript, nodejs_24, autoPatchelfHook, xdg-utils }:
let
  src = fetchFromGitHub {
    owner = "zakkoo";
    repo = "proton-drive-sync";
    rev = "1ef9829826bcc06286c7b4093fbc2c3019cce53a";
    hash = "sha256-QgmtH8EGXlT369nyNXjNZ9AM64tsOCch/RCB8cClVRw=";
  };
  engine = buildNpmPackage {
    pname = "proton-drive-sync";
    version = "0.1.0-unstable-1ef9829";
    inherit src;
    nodejs = nodejs_24;
    npmDepsHash = "sha256-oLo5PzmGjMZ0u5ZJld1wQ3c9/AyKhrc2VyLXIwdzko8=";
    # @parcel/watcher's prebuilt addon (libstdc++).
    nativeBuildInputs = [ autoPatchelfHook ];
    buildInputs = [ stdenv.cc.cc.lib ];
    installPhase = ''
      runHook preInstall
      npm prune --omit=dev --no-save
      rm -rf node_modules/@parcel/watcher-*-musl
      mkdir -p $out/lib/proton-drive-sync
      cp -r dist node_modules package.json $out/lib/proton-drive-sync/
      runHook postInstall
    '';
  };
  runtime = "${engine}/lib/proton-drive-sync";
  launcher = writeScript "proton-drive-sync" ''
    #!/usr/bin/env bash
    # installed-by=io.github.zakkoo.proton-drive
    # runtime=${runtime}
    exec ${nodejs_24}/bin/node "${runtime}/dist/cli/main.js" "$@"
  '';
in
{
  inherit src;
  home.".local/bin/proton-drive-sync" = launcher;
  packages = [ xdg-utils ];
  meta.description = "Proton Drive sync (its engine built with buildNpmPackage, launcher at ~/.local/bin)";
}
