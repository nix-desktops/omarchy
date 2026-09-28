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
        path). Or give `url`, `rev` and `hash`. Without either, a plugin in
        the flake's registry (pkgs/plugins, `lib.plugins`) is installed from
        its entry, helpers and all; any other entry only adds `packages` for
        a plugin added with `omarchy plugin add`.
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

    registry = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Without `src`/`url`: install the plugin from the flake's registry of
        packaged plugins (pkgs/plugins/<id>) when it's there. Its
        `helpers`, `home`, `packages`, … come first; the ones set here are
        added (and win per path). Set false to keep a plugin added with
        `omarchy plugin add` and only give it `packages`.
      '';
    };

    helpers = mkOption {
      type = types.attrsOf (types.either types.path types.str);
      default = { };
      example = lib.literalExpression ''{ "bin/weatherd" = lib.getExe weatherd; }'';
      description = ''
        Nix-built programs placed inside the plugin's own tree, at paths
        relative to its root, where the plugin looks for them (`bin/x`,
        `target/release/x`). Copied, not linked (upstream's validator refuses
        symlinks). Needs `src`/`url` or a registry entry: the plugin is a
        store path built with them.
      '';
    };

    home = mkOption {
      type = types.attrsOf (types.either types.path types.str);
      default = { };
      example = lib.literalExpression ''
        {
          ".local/bin/weather-helper" = lib.getExe weather-helper;
          ".local/share/acme.weather/venv" = pkgs.python3.withPackages (ps: [ ps.requests ]);
        }
      '';
      description = ''
        Links in the home (Home Manager `home.file`, relative to $HOME) for
        paths a plugin hardcodes: `~/.local/bin/x`, a venv at
        `~/.local/share/<name>/venv` (a python3.withPackages has
        bin/python and bin/python3 like one).
      '';
    };

    patches = mkOption {
      type = types.listOf types.path;
      default = [ ];
      description = "Patches applied to the plugin's files before it's validated (declared plugins only).";
    };

    postPatch = mkOption {
      type = types.lines;
      default = "";
      example = lib.literalExpression ''"substituteInPlace bin/run --replace-fail '$HOME/.venv/bin/python' ''${python}/bin/python"'';
      description = ''
        Shell run in the plugin's files after `patches` (substituteInPlace
        …): a download step or a venv path replaced by a store path.
      '';
    };

    hyprlandPlugins = mkOption {
      type = types.listOf types.package;
      default = [ ];
      description = ''
        Hyprland compositor plugins this plugin needs, loaded by the
        generated hyprland.lua (`hl.plugin.load`). Build them with
        `mkHyprlandPlugin` against the desktop's Hyprland (a registry
        entry gets both as arguments).
      '';
    };

    hyprlandConfig = mkOption {
      type = types.lines;
      default = "";
      description = "Hyprland Lua for this plugin, added to the generated hyprland.lua after its compositor plugins load.";
    };

    qmlModules = mkOption {
      type = types.listOf types.package;
      default = [ ];
      description = "QML modules (from Quickshell's Qt, nixos-unstable) added to the shell's import path for this plugin.";
    };
  };
})
