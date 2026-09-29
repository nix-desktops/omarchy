# Grammachy: Overlay.qml runs <plugin>/bin/grammachy (Rust, cli/: the Harper
# grammar engine built in), which the setup card downloads from GitHub
# releases (bin/bootstrap.sh). Pattern: a helper inside the plugin's tree.
{ lib, fetchFromGitHub, rustPlatform, runtimeShell, curl, wl-clipboard, nodejs, jq }:
let
  src = fetchFromGitHub {
    owner = "jyooi";
    repo = "grammachy";
    rev = "083199ab8bde03fc9ee8980b8fd416c787d99efe";
    hash = "sha256-+sszG/hh3oFHp4oD2YOLynaFhEjia9fnupx0sGhHNnA=";
  };

  grammachy = rustPlatform.buildRustPackage {
    pname = "grammachy";
    version = "0.4.2-unstable-083199a";
    inherit src;
    sourceRoot = "${src.name}/cli";
    cargoHash = "sha256-LYbUUqDErTHjR6Cx4BVSJgDoFXN6OkE1n29cp5NPOhw=";
    # Its tests run bin/*.sh against stub scripts, all #!/usr/bin/env bash.
    postPatch = ''
      patchShebangs ../bin
      sed -i 's|#!/usr/bin/env bash|#!${runtimeShell}|' tests/bootstrap.rs tests/release_lock.rs
    '';
    # Its overlay tests read ui/capture.js with node; release-lock.sh uses jq.
    nativeCheckInputs = [ nodejs jq ];
    checkFlags = [
      # Runs systemctl --user.
      "--skip=the_engine_flag_wins_over_the_stored_engine"
      # These ask git about the checkout.
      "--skip=the_contributor_guide_is_tracked"
      "--skip=the_tracked_tree_carries_no_agent_instruction_file"
    ];
    meta.mainProgram = "grammachy";
  };
in
{
  inherit src;
  helpers."bin/grammachy" = lib.getExe grammachy;
  # Capture and paste go through wl-copy/wl-paste; curl is its doctor's.
  packages = [ curl wl-clipboard ];
  meta.description = "Grammar checker overlay (grammachy built from cli/)";
}
