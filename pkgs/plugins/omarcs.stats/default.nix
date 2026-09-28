# omarCS: CS2 demo stats. Panel.qml runs <plugin>/omarcs-plugin, which
# downloads a release into ~/.local/share/omarcs (or builds with cargo)
# and execs it. Pattern: the script patched to exec the Nix-built CLI.
{ lib, fetchFromGitHub, rustPlatform }:
let
  src = fetchFromGitHub {
    owner = "Kieren-Foenander";
    repo = "omarCS";
    rev = "a1e6075cb5795a9207a4f888f65e5dfd76db02a9";
    hash = "sha256-cOMtUYA4GMnRojHZeRwtfvmRZBq0BeBQeSZ3XWV8sfQ=";
  };

  omarcs = rustPlatform.buildRustPackage {
    pname = "omarcs";
    version = "0.1.2-unstable-a1e6075";
    inherit src;
    cargoHash = "sha256-iiv27YahbHq1u3QBqFXUpdDfC3IVVZnlIlmdIKzXwj4=";
    cargoBuildFlags = [ "-p" "omarcs" ];
    cargoTestFlags = [ "-p" "omarcs" ];
    meta.mainProgram = "omarcs";
  };
in
{
  inherit src;
  postPatch = ''
    substituteInPlace omarcs-plugin \
      --replace-fail 'plugin_dir="$(cd --' 'exec ${lib.getExe omarcs} "$@"
    plugin_dir="$(cd --'
  '';
  meta.description = "CS2 match stats (the omarcs CLI built from crates/omarcs)";
}
