# Omastonk: a market watchlist widget whose Rust backend runs from
# <plugin>/omarchy/bin/omastonk-qs, shipped prebuilt (static musl, so it
# runs as is). Built from the repo's crate instead, with nixos-unstable's
# Rust (it asks for 1.97.1). Pattern: a helper inside the plugin's tree,
# replacing a shipped binary.
{ lib, fetchFromGitHub, omarchyUnstable }:
let
  src = fetchFromGitHub {
    owner = "LucaNerlich";
    repo = "omastonk";
    rev = "f3843cacdcc95e1dfb25192db1f337fc6482817f";
    hash = "sha256-QsZ0pGKlK9HmbDo7bViiV15KEiSNFHhthA2MDv1mgq0=";
  };

  omastonk-qs = omarchyUnstable.rustPlatform.buildRustPackage {
    pname = "omastonk-qs";
    version = "2.1.2-unstable-f3843ca";
    inherit src;
    cargoHash = "sha256-IwWu01eViePg3bU1oaXpEzaGZXeTHI5G7OyV1p/vj60=";
    meta.mainProgram = "omastonk-qs";
  };
in
{
  inherit src;
  helpers."omarchy/bin/omastonk-qs" = lib.getExe omastonk-qs;
  meta.description = "Market watchlist (omastonk-qs built from source)";
}
