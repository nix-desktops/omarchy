# Omastorm: weather radar. ui/PluginSession.qml runs `run.sh --ensure`,
# which runs target/debug/omastorm-engine when it's there and otherwise
# downloads the pinned release engine (glibc-dynamic) into ~/.local/share.
# Built here from the workspace (engine/), with the geography it embeds
# unpacked from the repo's own data/fixtures. Pattern: a helper inside the
# plugin's tree.
{ lib, fetchFromGitHub, rustPlatform, cmake, cacert }:
let
  src = fetchFromGitHub {
    owner = "wesleygrimes";
    repo = "omastorm";
    rev = "cfaeb6d6adf6c149519bf23adf7e905b9a3c1719";
    hash = "sha256-z6RZ3uUdevBjKQwxZv7flhC0p315m2ysXRa0AQTCOMo=";
  };

  engine = rustPlatform.buildRustPackage {
    pname = "omastorm-engine";
    version = "0.1.10-unstable-cfaeb6d";
    inherit src;
    cargoHash = "sha256-0EAaaMq89rAQKJVQgS/TGAnaGcjG6ir6Ng98SuNZaq4=";
    nativeBuildInputs = [ cmake ]; # aws-lc-sys
    dontUseCmakeConfigure = true;
    # data/raw: gunzipped from data/fixtures and checked against data/SHA256SUMS.
    preBuild = "bash scripts/extract-fixtures.sh";
    # Its HTTP tests (local servers) build clients that load the system's CAs.
    # The daemon its protocol tests start keeps a cache under $HOME.
    preCheck = ''
      export SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt
      export HOME=$TMPDIR
    '';
    meta.mainProgram = "omastorm-engine";
  };
in
{
  inherit src;
  helpers."target/debug/omastorm-engine" = lib.getExe engine;
  meta.description = "Weather radar (omastorm-engine built from engine/)";
}
