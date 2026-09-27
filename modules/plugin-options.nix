# The type of `omarchy.plugins.<id>`, shared by the NixOS and Home Manager
# modules (the NixOS one passes its plugins down to every desktop user).
{ lib }:
let
  inherit (lib) mkOption types;
in
types.submodule ({ name, ... }: {
  options = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Whether this entry is in effect: the plugin installed (when it has a
        source) and switched on in the shell, and its packages installed.
      '';
    };

    src = mkOption {
      type = types.nullOr (types.either types.path types.package);
      default = null;
      example = lib.literalExpression ''
        pkgs.fetchFromGitHub { owner = "acme"; repo = "omarchy-weather"; rev = "…"; hash = "…"; }
      '';
      description = ''
        The plugin's files: a git checkout with manifest.json at its root
        (fetchgit / fetchFromGitHub, a flake input with `flake = false`, a
        path). Or give `url`, `rev` and `hash`. Without either, the entry
        only adds `packages` for a plugin added with `omarchy plugin add`.
      '';
    };

    url = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "https://github.com/acme/omarchy-weather.git";
      description = "The plugin's git repository, fetched at `rev` (fetchgit).";
    };

    rev = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "The commit (or tag) of `url` to install.";
    };

    hash = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      description = ''
        The hash of the checkout at `rev` (`nix run nixpkgs#nix-prefetch-git
        -- --url <url> --rev <rev>`, or build once with an empty hash and
        take the one Nix reports).
      '';
    };

    section = mkOption {
      type = types.nullOr (types.enum [ "left" "center" "right" ]);
      default = null;
      description = ''
        For a bar widget: the bar section it's placed in when it's first
        switched on (the manifest's `barWidget.defaultSection`, else
        center, when null). Moving it on the bar afterwards is the user's.
      '';
    };

    packages = mkOption {
      type = types.listOf types.package;
      default = [ ];
      example = lib.literalExpression "with pkgs; [ cava fprintd (python3.withPackages (ps: [ ps.requests ])) ]";
      description = ''
        Programs the plugin runs, installed for the user so they're on the
        shell's PATH (`omarchy plugin doctor ${name}` names them).
      '';
    };
  };
})
