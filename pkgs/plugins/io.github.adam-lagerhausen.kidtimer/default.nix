# Kidtimer: a parent/kid screen-time bank; the Go daemon is the plugin.
# BarWidget.qml runs ~/.local/bin/kidtimer, else <plugin>/bin/kidtimer;
# helpers/apply-role.sh installs <plugin>/kidtimer into ~/.local/bin, else
# downloads a release or go-builds it. Pattern: helpers inside the plugin's
# tree. The kid role installs a root service into /etc/systemd/system,
# which NixOS doesn't allow: the parent role works.
{ lib, fetchFromGitHub, buildGoModule }:
let
  src = fetchFromGitHub {
    owner = "adam-lagerhausen";
    repo = "omarchy-kidtimer";
    rev = "3c38841d381b088ae14e36a08c9960a6039be786";
    hash = "sha256-BMamcY7oovSK82EXrCBgpFUgfqtg1gZikGttDnssF8Q=";
  };

  kidtimer = buildGoModule {
    pname = "kidtimer";
    version = "0-unstable-3c38841";
    inherit src;
    vendorHash = "sha256-ph255q2dBwQzH/JcRoV8xghkyCtG+0H1VJDhF5F609M=";
    subPackages = [ "daemon/cmd/kidtimer" ];
    env.CGO_ENABLED = 0;
    # These run the plugin's shell helpers with PATH=/usr/bin:/bin, pkexec,
    # python3 and a live daemon: the Arch host, not the sandbox.
    checkFlags = [
      "-skip=^(TestApplyRole|TestHomeFromPkexec|TestInstallLibManifest|TestLiveDaemon|TestLoopbackHTTP|TestPrivilegedInstall|TestTestdata)"
    ];
    meta.mainProgram = "kidtimer";
  };
in
{
  inherit src;
  helpers."kidtimer" = lib.getExe kidtimer;
  helpers."bin/kidtimer" = lib.getExe kidtimer;
  meta.description = "Screen-time bank, parent role (kidtimer built from daemon/cmd/kidtimer)";
}
