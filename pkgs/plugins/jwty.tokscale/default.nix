# Tokscale: AI token usage in the bar. status.sh and open-tokscale.sh run the
# `tokscale` CLI from PATH (upstream: `npm install -g tokscale`, whose npm
# package wraps a Rust binary). Pattern: a package on PATH, built from
# junhoyeo/tokscale (the plugin names no version: the release current when
# the plugin was surveyed).
{ lib, fetchFromGitHub, omarchyUnstable, pkg-config, openssl, lsof, tzdata }:
let
  src = fetchFromGitHub {
    owner = "jwtiyar";
    repo = "omarchy-tokscale";
    rev = "e176f09be11135f888e268a9689c9dc501327e0b";
    hash = "sha256-KX66l8xD/07+rcCaka4cQT7icCwPeADOC9UTWcDSIZQ=";
  };

  # rust-toolchain.toml pins 1.98; 26.05 has 1.95.
  tokscale = omarchyUnstable.rustPlatform.buildRustPackage (finalAttrs: {
    pname = "tokscale";
    version = "4.17.0";
    src = fetchFromGitHub {
      owner = "junhoyeo";
      repo = "tokscale";
      tag = "v${finalAttrs.version}";
      hash = "sha256-YgJxly0r0p8iGu2dLuMmsfHR/Br0Wbq4Tjkj3SbzR8Q=";
    };
    cargoHash = "sha256-sJ9sSDP5AYEbRwZMEawNQZMC4/z91PfTqx6beOqVO28=";
    cargoBuildFlags = [ "-p" "tokscale-cli" ];
    cargoTestFlags = [ "-p" "tokscale-cli" ];
    nativeBuildInputs = [ pkg-config ];
    buildInputs = [ openssl ];
    env.OPENSSL_NO_VENDOR = 1; # the system's OpenSSL, not openssl-src
    # Its tests bucket by time zone.
    preCheck = "export TZDIR=${tzdata}/share/zoneinfo";
    # These detect the host's own zone (/etc/localtime), which the sandbox lacks.
    checkFlags = map (t: "--skip=${t}") [
      "test_auto_pinning_never_overwrites_a_settings_file_it_could_not_read"
      "test_auto_pinning_recovers_from_a_bucket_timezone_that_names_no_zone"
      "test_first_run_pins_the_host_timezone_without_changing_its_own_output"
      "test_graph_single_day_filter_uses_local_timezone_boundaries"
      "test_submit_dry_run_preserves_local_date_ahead_of_utc"
      "test_unpinned_first_scan_still_buckets_by_the_host_timezone"
    ];
    meta.mainProgram = "tokscale";
  });
in
{
  inherit src;
  packages = [ tokscale lsof ];
  meta.description = "AI token usage (the tokscale CLI built from source, on PATH)";
}
