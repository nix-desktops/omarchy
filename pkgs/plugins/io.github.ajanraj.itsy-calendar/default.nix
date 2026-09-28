# Itsy Calendar: Service.qml runs
# ~/.local/share/itsy-calendar/bin/itsy-calendar-engine, which upstream's
# setup downloads. The engine wants Rust 1.97: nixos-unstable's toolchain.
# Pattern: a link in the home.
{ lib, fetchFromGitHub, omarchyUnstable, libcanberra-gtk3, curl }:
let
  src = fetchFromGitHub {
    owner = "ajanraj";
    repo = "itsy-calendar";
    rev = "6c987584dbdf036b3cad00d1072a481286d6f0d2";
    hash = "sha256-aBs48wPWZRsDbwDyF/6+9JKAq34eEoPJ91A+88Szfy4=";
  };

  engine = omarchyUnstable.rustPlatform.buildRustPackage {
    pname = "itsy-calendar-engine";
    version = "0.2.1-unstable-6c98758";
    inherit src;
    sourceRoot = "${src.name}/engine";
    cargoHash = "sha256-pNg3sd3x9FPl3M0uO6FyF4t84+/cGkpZ7Lt6LIhNiKg=";
    # Downloads a calendar with curl: no network in the sandbox.
    checkFlags = [ "--skip=management::tests::subscriptions_download_and_refresh_atomically" ];
    meta.mainProgram = "itsy-calendar-engine";
  };
in
{
  inherit src;
  home.".local/share/itsy-calendar/bin/itsy-calendar-engine" = lib.getExe engine;
  # Event sounds (canberra-gtk-play), URL calendars (curl).
  packages = [ libcanberra-gtk3 curl ];
  meta.description = "Calendar (itsy-calendar-engine built from engine/, linked in ~/.local/share)";
}
