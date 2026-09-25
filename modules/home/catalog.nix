# Everything in lib/catalog.nix, installed the way PACKAGES.md decides:
#
#   default    the CLI setup (`omarchy.cli.<id>.enable`) and the TUI
#              launchers (`omarchy.tuis.<id>.enable`): on, each opt-out
#   ecosystem  Omarchy's apps, web apps and development tools: one switch
#              (`omarchy.ecosystem.enable`, the installer's "Install entire
#              ecosystem") sets each layer's `enable`; `picks` keeps only
#              some of a layer
#   picked     AI agents and their CLIs (`omarchy.agents`, `omarchy.tools`):
#              only what's listed, never by default or with the ecosystem
#
# Upstream binds all its app and web-app keys together; the ones whose
# entry isn't installed here are removed from the Hyprland config.
{ inputs }:
{ config, lib, pkgs, omarchyUnstable, omarchyTools, ... }:
let
  cfg = config.omarchy;
  inherit (lib) mkOption types;

  catalog = import ../../lib/catalog.nix;

  resolve = attr:
    let
      parts = lib.splitString "." attr;
      sets = { unstable = omarchyUnstable; omarchy = omarchyTools; };
      scoped = sets ? ${lib.head parts} && lib.length parts > 1;
      set = if scoped then sets.${lib.head parts} else pkgs;
      path = if scoped then lib.tail parts else parts;
    in
    if lib.hasAttrByPath path set then lib.getAttrFromPath path set
    else throw "omarchy: catalog package '${attr}' isn't in this nixpkgs";

  ids = group: lib.attrNames catalog.${group};

  # Agents the menu installed (Setup > Defaults > Agent, omarchy-default-
  # agent): agents.json in the host's state directory, next to apps.json.
  agentsFile = cfg.stateDir + "/agents.json";
  agentState = { agents = [ ]; default = null; }
    // lib.optionalAttrs (builtins.pathExists agentsFile) (builtins.fromJSON (builtins.readFile agentsFile));
  knownAgent = id: catalog.agents ? ${id}
    || lib.warn "omarchy: unknown agent '${id}' in agents.json — skipped" false;
  # The default agent is installed too.
  agents = lib.unique (cfg.agents ++ lib.filter knownAgent agentState.agents
    ++ lib.optional (cfg.defaultAgent != null) cfg.defaultAgent);

  # For omarchy-default-agent: the agents, their commands and whether
  # nixpkgs has them.
  agentsJson = pkgs.writeText "omarchy-agents.json" (builtins.toJSON
    (lib.mapAttrs (_: a: { inherit (a) name command packaged; }) catalog.agents));

  # Default groups: an enable per program.
  optOuts = group: noun: lib.genAttrs (ids group) (id: {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Install ${catalog.${group}.${id}.name} (${noun}).";
    };
  });

  # Ecosystem layers: an enable (following the ecosystem switch) and picks.
  layer = group: noun: description: {
    enable = mkOption {
      type = types.bool;
      default = cfg.ecosystem.enable;
      defaultText = lib.literalExpression "config.omarchy.ecosystem.enable";
      inherit description;
    };
    picks = mkOption {
      type = types.listOf (types.enum (ids group));
      default = ids group;
      defaultText = lib.literalMD "every ${noun} in `lib.catalog.${group}`";
      description = "Which of Omarchy's ${noun}s to keep (ids from the flake's `lib.catalog.${group}`).";
    };
  };

  # What ends up installed, per group; entries not in nixpkgs yet drop out.
  installed = lib.filterAttrs (_: e: e.packaged) (
    lib.filterAttrs (id: _: cfg.cli.${id}.enable) catalog.cli
    // lib.mapAttrs' (id: e: lib.nameValuePair "tui:${id}" e)
      (lib.filterAttrs (id: _: cfg.tuis.${id}.enable) catalog.tuis)
    // lib.concatMapAttrs (group: _:
      lib.optionalAttrs cfg.${group}.enable
        (lib.mapAttrs' (id: e: lib.nameValuePair "${group}:${id}" e)
          (lib.getAttrs cfg.${group}.picks catalog.${group})))
      { apps = null; webapps = null; development = null; }
    // lib.mapAttrs' (id: e: lib.nameValuePair "agent:${id}" e) (lib.getAttrs agents catalog.agents)
    // lib.mapAttrs' (id: e: lib.nameValuePair "tool:${id}" e) (lib.getAttrs cfg.tools catalog.tools)
  );

  entries = lib.attrValues installed;
  packages = map resolve (lib.concatMap (e: e.attrs) (lib.filter (e: e.preinstalled) entries));

  # Launchers and their icons, under the names the desktop files use
  # ("Google Maps.png" → Icon=google-maps).
  iconName = file: lib.toLower (lib.replaceStrings [ " " ] [ "-" ] (lib.removeSuffix ".png" file));
  launcherFiles = lib.concatMap (e: e.launchers) entries;
  iconFiles = lib.concatMap (e: e.icons) entries;
  launchers = pkgs.runCommand "omarchy-launchers" { } ''
    mkdir -p $out/share/applications $out/share/icons/hicolor/256x256/apps
    ${lib.concatMapStrings (f: ''
      cp ${lib.escapeShellArg "${inputs.omarchy}/applications/${f}"} $out/share/applications/
    '') launcherFiles}
    ${lib.concatMapStrings (f: ''
      cp ${lib.escapeShellArg "${inputs.omarchy}/applications/icons/${f}"} \
        $out/share/icons/hicolor/256x256/apps/${iconName f}.png
    '') iconFiles}
  '';

  # Upstream's app and web-app binds whose entry isn't installed.
  keptBinds = lib.concatMap (e: e.binds) entries;
  allBinds = lib.concatMap (e: e.binds)
    (lib.concatMap lib.attrValues [ catalog.tuis catalog.apps catalog.webapps ]);
  droppedBinds = lib.filter (k: !lib.elem k keptBinds) allBinds;
in
{
  options.omarchy = {
    ecosystem.enable = lib.mkEnableOption ''
      Omarchy's whole ecosystem on top of the defaults: its apps, web apps
      and development tools, with the keybinds that launch them. Sets the
      default of `omarchy.apps.enable`, `omarchy.webapps.enable` and
      `omarchy.development.enable`'';

    cli = optOuts "cli" "Omarchy's CLI setup";
    tuis = optOuts "tuis" "one of Omarchy's TUI launchers, with its keybind";

    apps = layer "apps" "app" ''
      Omarchy's app picks (LibreOffice, Obsidian, OBS, Kdenlive, Pinta,
      Xournal++, …) and their keybinds (SUPER+SHIFT+O Obsidian, +M Spotify,
      +G Signal, …). Apps not in nixpkgs yet (Omarchy's own omacut,
      omawrite, …) are skipped with their binds.
    '';
    webapps = layer "webapps" "web app" ''
      Omarchy's web apps (HEY, YouTube, WhatsApp, Google Photos, X, …):
      their launchers and keybinds.
    '';
    development = layer "development" "development tool" ''
      Omarchy's development tools (mise, clang, ruby, lua, docker
      compose/buildx, …). Docker itself is the NixOS module's
      `omarchy.development.enable`.
    '';

    agents = mkOption {
      type = types.listOf (types.enum (ids "agents"));
      default = [ ];
      example = [ "claude" "codex" ];
      description = ''
        AI coding agents to install (upstream's agent names, from the
        flake's `lib.catalog.agents`), on top of the ones the menu installed
        (agents.json in `omarchy.stateDir`). The agent integration (the
        shell's agents panel, SUPER+SHIFT+CTRL+A, the scratchpad console) is
        always on; the agents themselves are a choice.
      '';
    };

    defaultAgent = mkOption {
      type = types.nullOr (types.enum (ids "agents"));
      default = if agentState.default != null && catalog.agents ? ${agentState.default}
        then agentState.default else null;
      defaultText = lib.literalMD "the menu's pick (agents.json), else none";
      example = "claude";
      description = ''
        The agent SUPER+SHIFT+CTRL+A and the scratchpad console open, as
        Setup > Defaults > Agent sets it (written to
        ~/.config/omarchy/defaults/agent); installed too. Null leaves the
        choice to the menu.
      '';
    };

    catalogFiles.agents = mkOption {
      type = types.package;
      readOnly = true;
      internal = true;
      default = agentsJson;
      description = "The agents catalog as JSON, for omarchy-default-agent.";
    };

    tools = mkOption {
      type = types.listOf (types.enum (ids "tools"));
      default = [ ];
      example = [ "gh" ];
      description = "CLIs upstream installs next to the agents (gh, playwright, …; ids from `lib.catalog.tools`).";
    };
  };

  config = lib.mkIf cfg.enable {
    # Low priority, like the default apps: a host's own package providing
    # the same command wins.
    home.packages = map lib.lowPrio packages
      ++ lib.optionals (launcherFiles != [ ]) [ launchers pkgs.hicolor-icon-theme ];

    omarchy.hyprland.droppedBinds = droppedBinds;

    # The default agent, where omarchy-default-agent keeps it. Written, not
    # linked, so the menu can still change it until the next rebuild.
    home.activation.omarchyDefaultAgent = lib.mkIf (cfg.defaultAgent != null)
      (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run mkdir -p "$HOME/.config/omarchy/defaults"
        run sh -c 'echo "$1" >"$2"' _ ${lib.escapeShellArg catalog.agents.${cfg.defaultAgent}.command} \
          "$HOME/.config/omarchy/defaults/agent"
      '');
  };
}
