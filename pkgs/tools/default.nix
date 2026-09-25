# Omarchy's own tools, each built from its upstream repo (a flake input) at
# the version Omarchy ships. Candidates for nixpkgs, one at a time.
{ pkgs, inputs }:
let
  callPackage = pkgs.lib.callPackageWith (pkgs // tools // { inherit inputs; });
  tools = {
    omasnap = callPackage ./omasnap.nix { };
    ttfx = callPackage ./ttfx.nix { };
    owe = callPackage ./owe.nix { };
    # A QML plugin for the shell: built against the Qt of the shell's
    # Quickshell (nixos-unstable), or Qt refuses to load it.
    owe-lockfeed = callPackage ./owe-lockfeed.nix {
      inherit (inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}) qt6;
    };
    elsewhen = callPackage ./elsewhen.nix { };
    omacut = callPackage ./qt-app.nix { pname = "omacut"; version = "0.4.0"; src = inputs.omacut; description = "Cut a video to the right trim"; extraQt = [ "qtmultimedia" ]; runtimePath = [ pkgs.ffmpeg ]; };
    omacalc = callPackage ./qt-app.nix { pname = "omacalc"; version = "0.2.2"; src = inputs.omacalc; description = "Omarchy's simple calculator"; launcher = "${inputs.omarchy-pkgs}/pkgbuilds/omacalc"; };
    omawrite = callPackage ./qt-app.nix { pname = "omawrite"; version = "0.5.0"; src = inputs.omawrite; description = "Distraction-free Markdown writing"; };
    aether = callPackage ./aether.nix { };
    herdr = callPackage ./herdr.nix { };
    tobi-try = callPackage ./tobi-try.nix { };
    omarchy-nvim = callPackage ./omarchy-nvim.nix { };
  };
in
tools
