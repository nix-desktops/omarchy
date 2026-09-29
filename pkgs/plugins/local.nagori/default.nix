# Nagori (the catalog's "Omastat"; its manifest id is local.nagori): app focus
# tracking. nagorid records focus into SQLite as a user service; the widget
# runs `nagori …` from ~/.cargo/bin, ~/.local/bin or PATH. Upstream's
# install.sh does cargo install plus the unit. Pattern: a package on PATH,
# and its user service (userServices).
{ lib, fetchFromGitHub, rustPlatform, writeText }:
let
  src = fetchFromGitHub {
    owner = "ThisIsRinesi";
    repo = "Omastat";
    rev = "a2407a07fc36da0c646cc43c14858eb5587c45a1";
    hash = "sha256-CvZveufFk7HxWKu1SMrNsfntabQTI/C8vvq0zanx10Y=";
  };

  nagori = rustPlatform.buildRustPackage {
    pname = "nagori";
    version = "0.2.0-unstable-a2407a0";
    inherit src;
    cargoHash = "sha256-73P74lZ0JouppvxBH3UCp+arXiSZ4Sgbl63QWqevBMA=";
    cargoBuildFlags = [ "-p" "nagori" ];
    # Its daemon tests stop it with /usr/bin/kill, which the sandbox lacks.
    postPatch = ''
      substituteInPlace crates/nagori/tests/daemon_lifecycle.rs \
        --replace-fail 'Command::new("/usr/bin/kill")' 'Command::new("kill")'
    '';
    checkFlags = [
      # Needs time zone data the sandbox doesn't have.
      "--skip=evening_routines_keep_local_times_and_distinct_dates_across_dst"
      # These time out in the sandbox (5 s).
      "--skip=stalled_snapshot_is_killed_on_timeout_and_on_shutdown"
      "--skip=disconnect_and_failed_snapshot_stop_focus_until_reconciliation_succeeds"
    ];
    meta.mainProgram = "nagori";
  };

  # packaging/systemd/nagori.service with the store's nagorid.
  service = writeText "nagori.service" ''
    [Unit]
    Description=Nagori app usage daemon
    After=graphical-session.target
    PartOf=graphical-session.target

    [Service]
    Type=simple
    ExecStart=${nagori}/bin/nagorid
    Restart=on-failure
    RestartSec=5s

    [Install]
    WantedBy=graphical-session.target
  '';
in
{
  inherit src;
  packages = [ nagori ];
  userServices."nagori.service" = service;
  meta.description = "App focus tracking (nagori and nagorid built from crates/nagori, user service)";
}
