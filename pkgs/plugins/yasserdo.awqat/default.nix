# Awqat: prayer times from the Rust helper. PrayerState.qml runs
# <plugin>/awqat-helper, which execs bin/awqat-core only when
# bin/source-checksums (sha256sum of Cargo.toml, Cargo.lock, src/*.rs, what
# build.sh writes) matches the sources. Pattern: a helper inside the
# plugin's tree, with the checksums written for it.
{ lib, fetchFromGitHub, rustPlatform, pkg-config, curl, tzdata }:
let
  src = fetchFromGitHub {
    owner = "iYassr";
    repo = "awqat";
    rev = "befec0e58b8168d43500dcdcd2012d65724e2ddd";
    hash = "sha256-JywahB5ZH3u63QyAo0uI0uFQ552mFMM6A0HK9BsMkyM=";
  };

  awqat-core = rustPlatform.buildRustPackage {
    pname = "awqat-core";
    version = "1.2.3-unstable-befec0e";
    inherit src;
    cargoHash = "sha256-CDwTto2uRWy33jGamrZaux4kNJE9qzEJW6PUh3dV06M=";
    nativeBuildInputs = [ pkg-config ];
    buildInputs = [ curl ];
    # Its tests look up time zones (jiff reads TZDIR).
    preCheck = "export TZDIR=${tzdata}/share/zoneinfo";
    meta.mainProgram = "awqat-core";
  };
in
{
  inherit src;
  helpers."bin/awqat-core" = lib.getExe awqat-core;
  postPatch = ''
    mkdir -p bin
    sha256sum Cargo.toml Cargo.lock src/*.rs > bin/source-checksums
  '';
  meta.description = "Prayer times (awqat-core built from the repo, with its source checksums)";
}
