# Feader RSS: Panel.qml runs <plugin>/feader-rss-fetch (the Go fetcher and
# SQLite store; scripts/install.sh builds it or downloads a release).
# go.mod asks for Go 1.27, which Nixpkgs doesn't have yet; it builds with
# 1.26. Pattern: a helper inside the plugin's tree.
{ lib, fetchFromGitHub, buildGoModule }:
let
  src = fetchFromGitHub {
    owner = "KitsuneSemCalda";
    repo = "Feader-RSS";
    rev = "ebe4ba6abce2ac6488cccd04763c126f83d5c718";
    hash = "sha256-CRWkqSPX8vN8ceQC6LFNbsonjoGRJnUImcIivS5KMdQ=";
  };

  fetcher = buildGoModule {
    pname = "feader-rss-fetch";
    version = "0-unstable-ebe4ba6";
    inherit src;
    postPatch = ''
      substituteInPlace go.mod --replace-fail 'go 1.27.0' 'go 1.26'
    '';
    vendorHash = "sha256-RSPUELy1STsImvtHre0i/fjfX989uhDPh2oS0k7FD+g=";
    subPackages = [ "cmd/feader-rss-fetch" ];
    env.CGO_ENABLED = 0;
    meta.mainProgram = "feader-rss-fetch";
  };
in
{
  inherit src;
  helpers."feader-rss-fetch" = lib.getExe fetcher;
  meta.description = "RSS reader (feader-rss-fetch built from cmd/)";
}
