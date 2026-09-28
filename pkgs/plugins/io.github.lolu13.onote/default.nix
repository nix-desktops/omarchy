# Onote: notes windows backed by a Rust helper (helper/: SQLite store,
# markdown, search). HelperClient.qml runs ~/.local/bin/onote-helper, which
# upstream's install.py builds with cargo. Pattern: a link in the home.
{ lib, fetchFromGitHub, rustPlatform, wl-clipboard }:
let
  src = fetchFromGitHub {
    owner = "lolu13";
    repo = "onote";
    rev = "0d83227f942a34cf671dd88e5e56c655b0bf3a7a";
    hash = "sha256-dM9jKwBR0OKkUm7S81AidIjxxUyzJCeOAj2SoH0DPcE=";
  };

  onote-helper = rustPlatform.buildRustPackage {
    pname = "onote-helper";
    version = "1.0.0-unstable-0d83227";
    inherit src;
    sourceRoot = "${src.name}/helper";
    cargoHash = "sha256-GRvHxHfEHri/xwmyatm9o3gt0ls4QxIiqKoiBqLr8FE=";
    # The clipboard at /usr/bin (run with PATH=/usr/bin): the store's.
    postPatch = ''
      substituteInPlace src/main.rs \
        --replace-fail '"/usr/bin/wl-paste"' '"${wl-clipboard}/bin/wl-paste"' \
        --replace-fail '"/usr/bin/wl-copy"' '"${wl-clipboard}/bin/wl-copy"'
    '';
    # These run /usr/bin/cat, /usr/bin/sh, …, which the sandbox lacks.
    checkFlags = [
      "--skip=fsutil::tests::bounded_run_caps_bytes_and_time"
      "--skip=fsutil::tests::feed_detached_succeeds_only_when_the_input_was_accepted"
    ];
    meta.mainProgram = "onote-helper";
  };
in
{
  inherit src;
  home.".local/bin/onote-helper" = lib.getExe onote-helper;
  meta.description = "Notes windows (onote-helper built from helper/, linked at ~/.local/bin)";
}
