# nixpkgs' command → package database (programs.sqlite, what NixOS's
# command-not-found uses), for `omarchy plugin doctor`: which nixpkgs
# package provides a command a plugin runs.
#
# Why this one: it is made from the same release this flake follows
# (nixos-26.05), so the attribute names it gives are the ones a host's
# `pkgs` has; it lists top-level attributes only (what goes into
# `environment.systemPackages` / `omarchy.plugins.<id>.packages`); and it is
# 16 MB, offline once built. nix-index-database's prebuilt index covers
# every output file but is ~10x larger, follows nixos-unstable and answers
# with sub-attributes (`python3Packages.foo.out`).
#
# Only the sqlite file is kept from the channel tarball, so hosts download
# 16 MB (from the binary cache) rather than the whole channel. To move it
# to a newer channel release:
#   nix flake prefetch --json https://channels.nixos.org/nixos-26.05/nixexprs.tar.xz
# gives the release's immutable URL (`locked.url`); then
#   nix store prefetch-file <that URL>
# gives the hash.
{ runCommand, fetchurl, xz }:

let
  channel = fetchurl {
    url = "https://releases.nixos.org/nixos/26.05/nixos-26.05.10718.5e2305d577ca/nixexprs.tar.xz";
    hash = "sha256-jV7AGdlUuVGQOB5djEY9Q2uYhXqM3PeHmSjE1eqeoNM=";
  };
in
runCommand "nixpkgs-programs-db-26.05" { nativeBuildInputs = [ xz ]; } ''
  mkdir -p $out
  tar -xJf ${channel} --wildcards --no-anchored --strip-components=1 -C $out '*/programs.sqlite'
  test -s $out/programs.sqlite
''
