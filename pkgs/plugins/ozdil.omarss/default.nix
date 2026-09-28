# OmaRSS: an RSS panel. Panel.qml runs <plugin>/omarss-engine (Rust, the
# repo's crate), which omarss-dashboard compiles with cargo. Pattern: a
# helper inside the plugin's tree.
{ lib, fetchFromGitHub, rustPlatform, curl, xdg-utils }:
let
  src = fetchFromGitHub {
    owner = "ozdil";
    repo = "omarchy-omarss";
    rev = "6f29bd1a390421ca9023d90d0a1bd363906e7ef5";
    hash = "sha256-0gy7sOWuZ41aAS+sW8uFPeb6UXL78FGxta+ymeQLdCg=";
  };

  omarss-engine = rustPlatform.buildRustPackage {
    pname = "omarss-engine";
    version = "1.0.0-unstable-6f29bd1";
    inherit src;
    cargoHash = "sha256-0VsvLAwh1oxpO5dyNGQlkUePxEnSEH1tsxuUXTi+++Y=";
    meta.mainProgram = "omarss-engine";
  };
in
{
  inherit src;
  helpers."omarss-engine" = lib.getExe omarss-engine;
  # The engine fetches feeds with curl; links open with xdg-open.
  packages = [ curl xdg-utils ];
  meta.description = "RSS reader (omarss-engine built from source)";
}
