# SuperNotch: a notch of cards; the world clock and weather cards run Rust
# backends shipped prebuilt at plugins/<card>/bin/<arch>/ (glibc-dynamic,
# so they'd need nix-ld). Built from their plugins/<card>/rust instead.
# Pattern: helpers inside the plugin's tree, replacing shipped binaries.
{ lib, fetchFromGitHub, rustPlatform, glib }:
let
  src = fetchFromGitHub {
    owner = "avillagran";
    repo = "omarchy-supernotch";
    rev = "339feb004d34b032a9ae76fa32bbc8ba87502a06";
    hash = "sha256-1yPiqwn90MCyoF7GinjN5qDy2d7xA7u0OQajiJGNu/g=";
  };

  backend = card: cargoHash: rustPlatform.buildRustPackage {
    pname = "supernotch-${card}";
    version = "0-unstable-339feb0";
    inherit src cargoHash;
    sourceRoot = "${src.name}/plugins/${card}/rust";
    # The clock's tests read /usr/share/zoneinfo (the desktop has it:
    # omarchy.usrShare) and the local zone, which the sandbox lacks.
    checkFlags = [
      "--skip=tests::search_accepts_city_names_with_spaces"
      "--skip=tests::selected_zone_defaults_to_the_local_zone_when_removed"
    ];
    meta.mainProgram = "supernotch-${card}";
  };
  clock = backend "clock" "sha256-Y6lTbICgLocJml2eB//oCBo6nn30fucS/16J0thK318=";
  weather = backend "weather" "sha256-yKgLNb7FfUMRGYWsPAkSnkbloEL0Z80jdqTw64ZAOOI=";
in
{
  inherit src;
  helpers."plugins/clock/bin/x86_64/supernotch-clock" = lib.getExe clock;
  helpers."plugins/weather/bin/x86_64/supernotch-weather" = lib.getExe weather;
  # gdbus (media and notifications cards).
  packages = [ glib ];
  meta.description = "Notch cards (clock and weather backends built from plugins/*/rust)";
}
