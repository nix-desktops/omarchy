# herdr's own Nix package (nix/package.nix upstream), built with
# nixos-unstable's Rust: it pins a newer toolchain than 26.05 ships.
{ inputs, stdenv }:
let
  unstable = inputs.nixpkgs-unstable.legacyPackages.${stdenv.hostPlatform.system};
in
unstable.callPackage "${inputs.herdr}/nix/package.nix" { }
