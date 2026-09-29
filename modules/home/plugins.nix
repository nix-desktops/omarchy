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
{ config, lib, pkgs, omarchyUnstable, ... }@args:
let
  cfg = config.omarchy;
  inherit (lib) mkOption types;

  mkPlugin = pkgs.callPackage ../../pkgs/plugin.nix { omarchySrc = inputs.omarchy; };

  # The registry of packaged plugins (pkgs/plugins), built against this
  # desktop's Hyprland.
  registry = import ../../pkgs/plugins { inherit lib; };
  registryEntries = registry.entries {
    inherit pkgs omarchyUnstable;
    hyprland = cfg.hyprland.package;
    omarchySrc = inputs.omarchy;
  };

  # A declared plugin with its registry entry folded in: the entry's
  # helpers, links, packages, … first, the declaration's added on top.
  fromRegistry = id: p: p.registry && p.src == null && p.url == null && lib.elem id registry.ids;
  effective = id: p:
    if !(fromRegistry id p) then p // { entry = null; } else
    let e = registryEntries.${id}; in p // {
      entry = e;
      helpers = e.helpers // p.helpers;
      home = e.home // p.home;
      packages = e.packages ++ p.packages;
      patches = e.patches ++ p.patches;
      postPatch = e.postPatch + p.postPatch;
      hyprlandPlugins = e.hyprlandPlugins ++ p.hyprlandPlugins;
      hyprlandConfig = e.hyprlandConfig + p.hyprlandConfig;
      qmlModules = e.qmlModules ++ p.qmlModules;
      userServices = e.userServices // p.userServices;
      extraGroups = e.extraGroups ++ p.extraGroups;
      services = e.services ++ p.services;
      section = if p.section != null then p.section else e.section;
    };

  enabled = lib.mapAttrs effective (lib.filterAttrs (_: p: p.enable) cfg.plugins);
  sourced = lib.filterAttrs (_: p: p.src != null || p.url != null || p.entry != null) enabled;

  pluginPackage = id: p: mkPlugin {
    inherit id;
    inherit (p) patches postPatch helpers;
    src = if p.entry != null then p.entry.src
      else if p.src != null then p.src else pkgs.fetchgit {
        inherit (p) url rev;
        hash = if p.hash != null then p.hash else lib.fakeHash;
      };
  };
  built = lib.mapAttrs pluginPackage sourced;

  # Their systemd user units, laid out as ~/.config/systemd/user (the
  # wants links from each unit's [Install], ReadWritePaths made first):
  # pkgs/plugin-user-units.py.
  unitList = lib.concatLists (lib.mapAttrsToList (id: p: lib.mapAttrsToList (name: u:
    let
      spec = if builtins.isAttrs u && !(lib.isDerivation u) && !(u ? outPath) then u else
        if builtins.isString u && (lib.hasInfix "\n" u || !lib.hasPrefix "/" u) then { text = u; } else { source = u; };
    in {
      inherit name;
      source =
        if spec.text or null != null then pkgs.writeText "${lib.replaceStrings [ "/" ] [ "-" ] name}" spec.text
        else "${spec.source}";
      wantedBy = spec.wantedBy or null;
    }) p.userServices) enabled);
  userUnits = pkgs.runCommand "omarchy-plugin-user-units" {
    units = builtins.toJSON unitList;
    passAsFile = [ "units" ];
  } ''
    mkdir $out
    ${pkgs.python3}/bin/python3 ${../../pkgs/plugin-user-units.py} "$unitsPath" $out ${pkgs.coreutils}/bin/mkdir
  '';

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

    internal.pluginExtraGroups = mkOption {
      internal = true;
      type = types.listOf types.str;
      default = [ ];
      description = "Groups declared plugins need the user in (their `extraGroups`), for the NixOS module.";
    };

    internal.pluginServices = mkOption {
      internal = true;
      type = types.attrsOf (types.listOf types.str);
      default = { };
      description = "NixOS options declared plugins need on (their `services`), by plugin id.";
    };

    internal.pluginQmlModules = mkOption {
      internal = true;
      type = types.listOf types.package;
      default = [ ];
      description = "QML modules declared plugins add (their `qmlModules`, omarchy.qtWebEngine).";
    };

    qmlModules = mkOption {
      type = types.listOf types.package;
      default = with omarchyUnstable.kdePackages; [ qt5compat qtmultimedia qtwebsockets qtpositioning qtlottie qtquick3d ];
      defaultText = lib.literalExpression
        "with nixpkgs-unstable.kdePackages; [ qt5compat qtmultimedia qtwebsockets qtpositioning qtlottie qtquick3d ]";
      description = ''
        Qt QML modules the shell can import beyond Quickshell's own
        (QtQuick, Qt.labs.*, Quickshell.*): community plugins import
        Qt5Compat.GraphicalEffects, QtMultimedia, QtWebSockets,
        QtPositioning, Qt.labs.lottieqt and QtQuick3D, which Omarchy's
        Arch packages bring along or Arch users install. They must come
        from the Qt the shell runs on (nixos-unstable's, like Quickshell).
        A declared plugin's own `qmlModules` are added to these.
      '';
    };

    qtWebEngine.enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        QtWebEngine (Chromium; ~600 MB) on the shell's QML import path,
        for the few plugins that import QtWebEngine.
      '';
    };

    hyprland.package = mkOption {
      type = types.package;
      default = omarchyUnstable.hyprland;
      defaultText = lib.literalExpression "nixpkgs-unstable.hyprland (the NixOS module passes programs.hyprland.package)";
      description = ''
        The Hyprland the desktop runs, which compositor plugins (a declared
        plugin's `hyprlandPlugins`) are built against. The NixOS module
        sets it to `programs.hyprland.package`.
      '';
    };

    hyprland.plugins = mkOption {
      type = types.listOf (types.either types.package types.str);
      default = [ ];
      description = ''
        Hyprland compositor plugins the generated hyprland.lua loads
        (`hl.plugin.load`): a package with lib/lib<pname>.so (what
        mkHyprlandPlugin builds) or a path to the .so. Declared shell
        plugins' `hyprlandPlugins` are added here.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = lib.mapAttrsToList (id: p: {
      assertion = p.url == null || (p.src == null && p.rev != null && p.hash != null);
      message = "omarchy.plugins.\"${id}\": `url` needs `rev` and `hash` (and no `src`).";
    }) enabled ++ lib.mapAttrsToList (id: p: {
      assertion = sourced ? ${id} || (p.helpers == { } && p.patches == [ ] && p.postPatch == "");
      message = "omarchy.plugins.\"${id}\": `helpers`, `patches` and `postPatch` need the plugin declared with a source (`src`, `url`, or a registry entry).";
    }) enabled;

    # Without the NixOS module (Home Manager on its own) groups and system
    # services are the system's to add.
    warnings = lib.optional (!(args ? osConfig) && config.omarchy.internal.pluginExtraGroups != [ ])
      "omarchy.plugins: add this user to the groups ${lib.concatStringsSep ", " config.omarchy.internal.pluginExtraGroups} (users.users.<name>.extraGroups); the plugins declared need them."
      ++ lib.optionals (!(args ? osConfig)) (lib.concatLists (lib.mapAttrsToList (id: paths:
        map (path: "omarchy.plugins.\"${id}\" needs `${path} = true;` in the NixOS configuration.") paths)
        config.omarchy.internal.pluginServices));

    home.packages = lib.concatMap (p: p.packages) (lib.attrValues enabled);

    # Paths plugins hardcode in the home: ~/.local/bin/x, a venv.
    home.file = lib.mkMerge (lib.mapAttrsToList (_: p:
      lib.mapAttrs (_: target: { source = target; }) p.home) enabled);

    omarchy.internal.pluginExtraGroups = lib.unique (lib.concatMap (p: p.extraGroups) (lib.attrValues enabled));
    omarchy.internal.pluginServices = lib.filterAttrs (_: s: s != [ ]) (lib.mapAttrs (_: p: p.services) enabled);

    omarchy.internal.pluginQmlModules = lib.concatMap (p: p.qmlModules) (lib.attrValues enabled)
      ++ lib.optional cfg.qtWebEngine.enable omarchyUnstable.kdePackages.qtwebengine;

    omarchy.hyprland.plugins = lib.concatMap (p: p.hyprlandPlugins) (lib.attrValues enabled);
    omarchy.hyprland.extraConfig = lib.concatStrings (lib.mapAttrsToList (id: p:
      lib.optionalString (p.hyprlandConfig != "") "-- omarchy.plugins.\"${id}\"\n${p.hyprlandConfig}\n") enabled);

    xdg.configFile = lib.mapAttrs' (id: pkg:
      lib.nameValuePair "omarchy/plugins/${id}" { source = pkg; }) built
      # Plugins' user units, linked file by file among Home Manager's own
      # (sd-switch starts, restarts and stops them on switch).
      // lib.optionalAttrs (unitList != [ ]) {
        "systemd/user" = { source = userUnits; recursive = true; };
      };

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
