# Omarchy's shell plugins on NixOS.
#
# Upstream's own plugin commands work as they do on Arch (`omarchy plugin
# add <git-url>` clones into ~/.config/omarchy/plugins, `update`, `remove`,
# `enable`, `disable`, `clone`): git, gum, jq and ripgrep are on their PATH,
# the directory is the user's, and the shell watches and scans it.
#
# `omarchy.plugins.<id>` declares plugins instead, pinned in the config:
#   - with `src` (or `url` + `rev` + `hash`): the plugin is built
#     (lib.mkPlugin: its files, validated) and linked at
#     ~/.config/omarchy/plugins/<id>, where the shell discovers it like one
#     added by hand. `omarchy plugin update` leaves it alone (no .git);
#     `remove` unlinks it until the next activation.
#   - switched on through upstream's shell.json rules: in the package's
#     default layout, and once in the user's own shell.json when there is
#     one; switching it off or moving it afterwards is the user's
#     (pkgs/plugins-shell-json.py);
#   - `packages`: what it runs, installed for the user so it's on the
#     shell's PATH. An entry with only `packages` serves a plugin added
#     with `omarchy plugin add` (`omarchy plugin doctor <id>` prints it).
#
# `omarchy plugin doctor [id|path]` (pkgs/plugin-doctor.nix) reads a
# plugin's files and names what's missing and the nixpkgs packages for it.
{ inputs }:
{ config, lib, pkgs, omarchyUnstable, ... }:
let
  cfg = config.omarchy;
  inherit (lib) mkOption types;

  mkPlugin = pkgs.callPackage ../../pkgs/plugin.nix { omarchySrc = inputs.omarchy; };

  enabled = lib.filterAttrs (_: p: p.enable) cfg.plugins;
  sourced = lib.filterAttrs (_: p: p.src != null || p.url != null) enabled;

  pluginPackage = id: p: mkPlugin {
    inherit id;
    src = if p.src != null then p.src else pkgs.fetchgit {
      inherit (p) url rev;
      hash = if p.hash != null then p.hash else lib.fakeHash;
    };
  };
  built = lib.mapAttrs pluginPackage sourced;

  declaredJson = pkgs.writeText "omarchy-declared-plugins.json" (builtins.toJSON
    (lib.mapAttrsToList (id: p: {
      inherit id;
      inherit (p) section;
      manifest = "${built.${id}}/manifest.json";
    }) sourced));
in
{
  options.omarchy = {
    plugins = mkOption {
      type = types.attrsOf (import ../plugin-options.nix { inherit lib; });
      default = { };
      example = lib.literalExpression ''
        {
          # Declared: pinned, installed and switched on.
          "acme.weather" = {
            url = "https://github.com/acme/omarchy-weather.git";
            rev = "0123456789abcdef0123456789abcdef01234567";
            hash = "sha256-…";
            section = "right";
            packages = [ pkgs.curl ];
          };
          # Added with `omarchy plugin add`: only what it runs.
          "someone.cava" = { packages = [ pkgs.cava ]; };
        }
      '';
      description = ''
        Omarchy shell plugins, by manifest id. With a source (`src`, or
        `url` + `rev` + `hash`) the plugin is installed into
        ~/.config/omarchy/plugins/<id> and switched on the way upstream
        records it in ~/.config/omarchy/shell.json (once: switching it off
        from the shell afterwards sticks). `packages` go on the shell's
        PATH; `omarchy plugin doctor <id>` says which a plugin needs.
      '';
    };

    internal.declaredPlugins = mkOption {
      internal = true;
      type = types.listOf types.attrs;
      default = [ ];
      description = "Declared plugins with a source: id, section and the built plugin (dir), for the package.";
    };

    qmlModules = mkOption {
      type = types.listOf types.package;
      default = with omarchyUnstable.kdePackages; [ qt5compat qtmultimedia ];
      defaultText = lib.literalExpression "with nixpkgs-unstable.kdePackages; [ qt5compat qtmultimedia ]";
      description = ''
        Qt QML modules the shell can import beyond Quickshell's own
        (QtQuick, Quickshell.*): plugins use Qt5Compat.GraphicalEffects and
        QtMultimedia, which Omarchy's Arch packages bring along. They must
        come from the Qt the shell runs on (nixos-unstable's, like
        Quickshell).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = lib.mapAttrsToList (id: p: {
      assertion = p.url == null || (p.src == null && p.rev != null && p.hash != null);
      message = "omarchy.plugins.\"${id}\": `url` needs `rev` and `hash` (and no `src`).";
    }) enabled;

    home.packages = lib.concatMap (p: p.packages) (lib.attrValues enabled);

    xdg.configFile = lib.mapAttrs' (id: pkg:
      lib.nameValuePair "omarchy/plugins/${id}" { source = pkg; }) built;

    # For the package: declared plugins in the default layout.
    omarchy.internal.declaredPlugins = lib.mapAttrsToList (id: p: {
      inherit id;
      inherit (p) section;
      dir = built.${id};
    }) sourced;

    # Switched on in the user's own shell.json once, off when no longer
    # declared (pkgs/plugins-shell-json.py).
    home.activation.omarchyPlugins = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      run ${pkgs.python3}/bin/python3 ${../../pkgs/plugins-shell-json.py} activate ${declaredJson} \
        "$HOME/.config/omarchy/shell.json" "${config.xdg.stateHome}/omarchy/plugins.json"
    '';
  };
}
