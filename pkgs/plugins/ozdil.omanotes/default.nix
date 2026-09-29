# OmaNotes: encrypted notes. Panel.qml runs <plugin>/omanotes-engine; the
# wrappers (omanotes-status, omanotes-dashboard) build it with cargo and
# only run it with a provenance stamp over the plugin's own path, which a
# store path can't carry. Pattern: a helper in the plugin's tree, the
# wrappers' build and stamp gate patched out.
{ lib, fetchFromGitHub, rustPlatform }:
let
  src = fetchFromGitHub {
    owner = "ozdil";
    repo = "omarchy-omanotes";
    rev = "f51c4416582a4a1a716b7dc1498b2f67db95d55b";
    hash = "sha256-Ut3DEfEcHJX+vXmheN7yvx+pX7kpEK9wvPOBGHYbzRU=";
  };

  engine = rustPlatform.buildRustPackage {
    pname = "omanotes-engine";
    version = "1.0.0-unstable-f51c441";
    inherit src;
    cargoHash = "sha256-PhRpC+SYDVM7t0beBotJ6YJp4ZMyoRCmyBQOjNnWvBc=";
    # These run `cargo test` and git sync against /tmp: not in the sandbox.
    checkFlags = [
      "--skip=test_security_stubborn_grandchild_killed"
      "--skip=test_git_e2ee_cloud_sync_and_pull_roundtrip"
    ];
    meta.mainProgram = "omanotes-engine";
  };
in
{
  inherit src;
  helpers."omanotes-engine" = lib.getExe engine;
  postPatch = ''
    for f in omanotes-status omanotes-dashboard; do
      substituteInPlace $f \
        --replace-fail 'NEEDS_BUILD=1' 'NEEDS_BUILD=0' \
        --replace-fail '# Fail-closed execution gate' 'exec "''${BIN}" "$@" # Fail-closed execution gate'
    done
  '';
  meta.description = "Encrypted notes (omanotes-engine built from the repo)";
}
