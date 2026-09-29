# Security Sentinel: Panel.qml runs <plugin>/sentinel-engine (Rust: scans
# /proc, sockets, the journal), which sentinel-dashboard cargo-builds on
# first use. It calls /usr/bin/{ss,nft,kill,journalctl} (envfs finds them).
# Pattern: a helper inside the plugin's tree.
{ lib, fetchFromGitHub, rustPlatform, writeShellScriptBin, iproute2, nftables, procps, zenity }:
let
  src = fetchFromGitHub {
    owner = "ozdil";
    repo = "omarchy-security-sentinel";
    rev = "fb63eab5cfcae972db78363cda32eda4cb84ede4";
    hash = "sha256-0ktuHhA9HImnNhRPiQ+hQX3a6qG3FObZYDQkoMoPKDg=";
  };

  engine = rustPlatform.buildRustPackage {
    pname = "sentinel-engine";
    version = "1.0.0-unstable-fb63eab";
    inherit src;
    cargoHash = "sha256-lDnOpxqQGVdoeJt0tidM1xX18mYbNtSC678ilsA1z5w=";
    meta.mainProgram = "sentinel-engine";
  };

  # The panel's "open" runs sentinel-dashboard from PATH (upstream's PKGBUILD
  # installs it in /usr/bin).
  dashboard = writeShellScriptBin "sentinel-dashboard" ''
    exec "$HOME/.config/omarchy/plugins/ozdil.security-sentinel/sentinel-dashboard" "$@"
  '';
in
{
  inherit src;
  helpers."sentinel-engine" = lib.getExe engine;
  # It re-execs itself with PATH=/usr/bin:/bin and nothing else, where envfs
  # finds nothing: the system's and the user's profiles too.
  postPatch = ''
    substituteInPlace sentinel-dashboard \
      --replace-fail 'PATH="/usr/bin:/bin:''${HOME}/.local/bin:''${HOME}/.cargo/bin"' \
                     'PATH="/usr/bin:/bin:''${HOME}/.local/bin:''${HOME}/.cargo/bin:/run/current-system/sw/bin:/etc/profiles/per-user/''${USER:-$(/usr/bin/id -un)}/bin"'
  '';
  packages = [ iproute2 nftables procps zenity dashboard ];
  meta.description = "Security dashboard (sentinel-engine built from the repo)";
}
