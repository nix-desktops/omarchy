# Git Radar: Panel.qml runs <plugin>/gitradar-engine (Rust) for repository
# status. git-dashboard (the terminal view) cargo-builds it and refuses to
# run it without a provenance stamp: hashes of the sources (by absolute
# path) and of the binary. Pattern: a helper inside the plugin's tree, and
# the stamp written for it (the source hash taken by relative path).
{ lib, fetchFromGitHub, rustPlatform, writeShellScriptBin, git }:
let
  src = fetchFromGitHub {
    owner = "ozdil";
    repo = "omarchy-git-radar";
    rev = "8867042ecd8b03f4a93a4b43e7769a07977bee0d";
    hash = "sha256-o9jEhEZMBiL61/l7SPjFSINBY2NXFuUdSBPLQEpBB2E=";
  };

  engine = rustPlatform.buildRustPackage {
    pname = "gitradar-engine";
    version = "1.1.0-unstable-8867042";
    inherit src;
    cargoHash = "sha256-1NFpFzYoosDEhk4ztnaXBRlOxPPj6uoCaeHU/zoyres=";
    nativeCheckInputs = [ git ];
    # These run git with PATH=/usr/bin:/bin, which the sandbox lacks.
    checkFlags = [
      "--skip=tests::test_git_child_closes_stdout_and_sleeps_enforces_deadline"
      "--skip=tests::test_git_child_spawns_term_ignoring_background_descendant_retains_stdout"
    ];
    meta.mainProgram = "gitradar-engine";
  };

  # The panel's "open" runs git-dashboard from PATH (upstream's PKGBUILD
  # installs it in /usr/bin).
  dashboard = writeShellScriptBin "git-dashboard" ''
    exec "$HOME/.config/omarchy/plugins/ozdil.git-radar/git-dashboard" "$@"
  '';

  sourceHash = ''find src Cargo.toml Cargo.lock -type f | sort | xargs sha256sum | sha256sum | cut -d" " -f1'';
in
{
  inherit src;
  helpers."gitradar-engine" = lib.getExe engine;
  postPatch = ''
    # It re-execs itself with PATH=/usr/bin:/bin and nothing else, where
    # envfs finds nothing: the system's and the user's profiles too.
    substituteInPlace git-dashboard \
      --replace-fail 'PATH="/usr/bin:/bin:''${HOME}/.local/bin:''${HOME}/.cargo/bin"' \
                     'PATH="/usr/bin:/bin:''${HOME}/.local/bin:''${HOME}/.cargo/bin:/run/current-system/sw/bin:/etc/profiles/per-user/''${USER:-$(/usr/bin/id -un)}/bin"' \
      --replace-fail '/usr/bin/find "''${DIR}/src" "''${DIR}/Cargo.toml" "''${DIR}/Cargo.lock" -type f' \
                     'cd "''${DIR}" && /usr/bin/find src Cargo.toml Cargo.lock -type f'
    echo "$(${sourceHash}) $(sha256sum ${lib.getExe engine} | cut -d" " -f1)" > .engine-provenance
  '';
  packages = [ git dashboard ];
  meta.description = "Git repository dashboard (gitradar-engine built from the repo)";
}
