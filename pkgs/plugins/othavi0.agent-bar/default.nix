# Agent Bar: AI agents' usage on the bar. Service.qml runs
# <plugin>/bin/agent-bar, a Rust CLI shipped prebuilt (glibc-dynamic: it'd
# need nix-ld). Built from the repo's crate instead. Pattern: a helper
# inside the plugin's tree, replacing a shipped binary.
{ lib, fetchFromGitHub, rustPlatform }:
let
  src = fetchFromGitHub {
    owner = "othavi0";
    repo = "omarchy-agent-bar";
    rev = "bc7aff0034f332244e6cff11f0a5be3bd170d1c3";
    hash = "sha256-yKuYfmlGe89JEdSoyOAHFTXij5imSS4qQGO4HCYaWEM=";
  };

  agent-bar = rustPlatform.buildRustPackage {
    pname = "agent-bar";
    version = "10.6.3-unstable-bc7aff0";
    inherit src;
    # The integration tests (tests/) run git ls-files in the repository and
    # drive systemd user units: only the unit tests run. Of these, a few
    # spawn /bin/cat, /bin/sleep, /bin/bash, which the sandbox lacks.
    cargoTestFlags = [ "--bins" ];
    checkFlags = map (t: "--skip=${t}") [
      "providers::adapters::tests::codex_unauthenticated_appserver_reports_unauthenticated"
      "providers::process::tests::enforces_stdout_limit"
      "providers::process::tests::preserves_argv_and_exit_code"
      "providers::process::tests::stdin_is_closed_for_every_process"
      "providers::process::tests::timeout_kills_and_reaps"
      "providers::process::tests::timeout_kills_the_whole_process_group"
    ];
    cargoHash = "sha256-vh3rClos92r6hIlYywTKAi8+gI6S6O94hgslPD0gnCg=";
    meta.mainProgram = "agent-bar";
  };
in
{
  inherit src;
  helpers."bin/agent-bar" = lib.getExe agent-bar;
  meta.description = "AI agent usage (agent-bar built from source)";
}
