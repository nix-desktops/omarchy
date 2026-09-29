# Omarchy's Hyprland config: upstream's own Lua modules (look and feel,
# input, window rules, every keybind, autostart, the active theme's
# borders, window toggles), loaded straight from the Omarchy package, with
# this host's keybinds and extra config layered on top: the same shape as
# upstream's ~/.config/hypr/hyprland.lua.
{ inputs }:
{ config, lib, ... }:
let
  cfg = config.omarchy;
  inherit (lib) mkOption types;

  # Lua string literal (JSON strings are valid Lua strings).
  str = builtins.toJSON;

  bindType = types.submodule ({ name, ... }: {
    options = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Set to false to remove this key's bind (including Omarchy's default).";
      };
      description = mkOption {
        type = types.str;
        default = name;
        description = "Shown in the keybindings list (SUPER+K).";
      };
      exec = mkOption { type = types.nullOr types.str; default = null; description = "Shell command to run."; };
      launch = mkOption { type = types.nullOr types.str; default = null; description = "App to launch (uwsm-app)."; };
      webapp = mkOption { type = types.nullOr types.str; default = null; description = "URL to open as a web app."; };
      tui = mkOption { type = types.nullOr types.str; default = null; description = "Terminal app to open in a floating terminal."; };
      omarchy = mkOption { type = types.nullOr types.str; default = null; description = "An omarchy-launch-<name> launcher (terminal, browser, editor, …)."; };
      lua = mkOption { type = types.nullOr types.str; default = null; description = "Raw Hyprland Lua dispatcher, e.g. `hl.dsp.window.move({ direction = \"l\" })`."; };
      focus = mkOption {
        type = types.nullOr (types.either types.bool types.str);
        default = null;
        description = "Focus an existing window instead of opening another (true for web apps / TUIs, a class regex for `launch`).";
      };
      locked = mkOption { type = types.bool; default = false; description = "Also active on the lock screen."; };
      repeating = mkOption { type = types.bool; default = false; description = "Repeat while held."; };
    };
  });

  luaValue = v:
    if builtins.isBool v then (if v then "true" else "false") else str v;

  renderBind = keys: b:
    let
      focus = lib.optionalString (b.focus != null) ", focus = ${luaValue b.focus}";
      action =
        if b.lua != null then b.lua
        else if b.exec != null then str b.exec
        else if b.omarchy != null then "{ omarchy = ${str b.omarchy} }"
        else if b.webapp != null then "{ webapp = ${str b.webapp}${focus} }"
        else if b.tui != null then "{ tui = ${str b.tui}${focus} }"
        else if b.launch != null then "{ launch = ${str b.launch}${focus} }"
        else throw "omarchy.keybinds.\"${keys}\": set one of exec, launch, webapp, tui, omarchy or lua (or enable = false)";
      flags = lib.filter (f: f != "") [
        (lib.optionalString b.locked "locked = true")
        (lib.optionalString b.repeating "repeating = true")
      ];
      opts = lib.optionalString (flags != [ ]) ", { ${lib.concatStringsSep ", " flags} }";
    in
    if !b.enable then "hl.unbind(${str keys})"
    # What upstream's o.rebind does, spelled out: o.rebind is newer than
    # the stable channel's upstream release (v4.0.4 has only o.bind).
    else "hl.unbind(${str keys}); o.bind(${str keys}, ${str b.description}, ${action}${opts})";

  omarchyPath = "${config.home.homeDirectory}/.local/share/omarchy";
  store = "${cfg.package}/share/omarchy";

  # The cursor: home.pointerCursor (set from omarchy.cursor, or by the
  # host/Stylix), exported the way upstream's envs.lua exports its size.
  pointer = config.home.pointerCursor;
  cursorOn = pointer != null && pointer.enable;
  cursorEnv = lib.optionalString cursorOn ''

    -- The cursor theme (omarchy.cursor / home.pointerCursor). Upstream's
    -- envs.lua sets only the size and leaves the theme to the system.
    hl.env("XCURSOR_THEME", ${str pointer.name})
    hl.env("XCURSOR_SIZE", ${str (toString pointer.size)})
    hl.env("HYPRCURSOR_THEME", ${str pointer.name})
    hl.env("HYPRCURSOR_SIZE", ${str (toString (if pointer.hyprcursor.enable then pointer.hyprcursor.size else pointer.size))})
  '';

  # The system's keyboard layout (omarchy.keyboard, from the NixOS config's
  # services.xserver.xkb), where upstream reads XKBLAYOUT/XKBVARIANT from
  # /etc/vconsole.conf, which NixOS doesn't write. The same rule as upstream's
  # default/hypr/input.lua: a layout that can't type Latin letters gets "us"
  # in front, since Omarchy's binds resolve against the first layout.
  kb = cfg.keyboard;
  nonLatin = let m = builtins.match ".*non_latin_layouts =[[:space:]]*\"([^\"]*)\".*"
      (lib.replaceStrings [ "\n" ] [ " " ] (builtins.readFile (inputs.omarchy + "/default/hypr/input.lua")));
    in if m == null then [ ] else lib.filter (x: x != "") (lib.splitString " " (builtins.head m));
  kbVariant = if kb.variant == null then "" else kb.variant;
  kbLatinFirst = kb.layout != null && lib.elem (builtins.head (lib.splitString "," kb.layout)) nonLatin;
  keyboardLua = lib.optionalString (kb.layout != null) ''

    -- The system's keyboard layout (omarchy.keyboard); input.lua can change it.
    hl.config({ input = {
      kb_layout = ${str (if kbLatinFirst then "us,${kb.layout}" else kb.layout)},
      kb_variant = ${str (if kbLatinFirst then ",${kbVariant}" else kbVariant)},
    } })
  '';

  # A compositor plugin: mkHyprlandPlugin's lib/lib<pname>.so, or a path.
  hyprlandPluginPath = p: if lib.isString p then p else "${p}/lib/lib${p.pname}.so";

  hyprlandLua = ''
    -- Generated by nix-desktops/omarchy (Home Manager). Omarchy's own
    -- Hyprland config, loaded from the Omarchy package, then this host's
    -- keybinds and extra config. Edit the NixOS config, not this file.

    local home = os.getenv("HOME")

    -- Omarchy's bootstrap: reload its modules on every `hyprctl reload`.
    for module in pairs(package.loaded) do
      if module:find("^default%.hypr") or module:find("^hypr%.") or module:find("^omarchy%.") then
        package.loaded[module] = nil
      end
    end
    -- Lua modules from the store path, which exists before this file does:
    -- Hyprland reloads the moment activation rewrites it, possibly before
    -- the ~/.local/share/omarchy link is in place.
    package.path = home .. "/.local/state/?.lua;"
      .. home .. "/.config/?.lua;"
      .. ${str store} .. "/?.lua;"
      .. package.path
    package.loaded["default.hypr.paths"] = {
      home = home,
      config_home = home .. "/.config",
      state_home = home .. "/.local/state",
      omarchy_path = ${str store},
    }
    ${lib.optionalString (cfg.hyprland.plugins != [ ]) (''
      -- Compositor plugins (omarchy.hyprland.plugins, shell plugins'
      -- hyprlandPlugins), built against this Hyprland.
    '' + lib.concatMapStrings (p: "hl.plugin.load(${str (hyprlandPluginPath p)})\n") cfg.hyprland.plugins)}
    -- Omarchy's app and web-app binds (SUPER+SHIFT+M Spotify, …). The
    -- ones whose app isn't installed are removed below (catalog.nix).
    _G.omarchy_preinstalled_bindings = true

    -- Hyprland < 0.56 (a session still running the previous version after a
    -- switch, until the next login) lacks APIs Omarchy's quake-console
    -- scratchpad uses. Skip that one module there rather than fail the whole
    -- config; on 0.56 it loads as upstream intends.
    -- Probe the field qconsole needs (no hyprctl here: it would deadlock
    -- Hyprland, which can't answer its socket while evaluating this file).
    local monitors = hl.get_monitors() or {}
    if monitors[1] and monitors[1].reserved == nil then
      package.loaded["default.hypr.qconsole"] = true
    end

    require("default.hypr.omarchy")

    -- Commands and the shell's IPC use the stable path: Quickshell matches
    -- the running shell by its config path, which must not change between
    -- rebuilds (Omarchy's envs.lua just set the store path).
    hl.env("OMARCHY_PATH", ${str omarchyPath})
    ${cursorEnv}${keyboardLua}
    -- Binds of apps and web apps that aren't installed.
    ${lib.concatMapStringsSep "\n" (k: "hl.unbind(${str k})") cfg.hyprland.droppedBinds}

    -- Keybinds from omarchy.keybinds.
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList renderBind cfg.keybinds)}

    -- omarchy.hyprland.extraConfig
    ${cfg.hyprland.extraConfig}

    -- The user's own files, loaded after Omarchy's defaults and this host's
    -- NixOS config, as upstream's ~/.config/hypr/hyprland.lua does. They are
    -- regular files the user edits (seeded once from upstream's config/hypr;
    -- the menu's Setup > Monitors / Keybindings / Input and Style > Hyprland
    -- open them), so edits survive rebuilds.
    local optional = require("default.hypr.require_optional")
    optional.module("hypr.monitors")
    optional.module("hypr.input")
    optional.module("hypr.bindings")
    optional.module("hypr.looknfeel")
    optional.module("hypr.autostart")

    require("default.hypr.toggles")
  '';
in
{
  options.omarchy = {
    hyprland = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Write ~/.config/hypr/hyprland.lua: Omarchy's Hyprland config plus this host's keybinds and extra config.";
      };
      droppedBinds = mkOption {
        type = types.listOf types.str;
        default = [ ];
        internal = true;
        description = "Upstream binds to remove: apps and web apps that aren't installed (set by catalog.nix).";
      };
      extraConfig = mkOption {
        type = types.lines;
        default = "";
        description = "Hyprland Lua appended after Omarchy's config and the keybinds (monitors, input devices, window rules, …).";
      };
    };

    keyboard = {
      layout = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "de,us";
        description = ''
          XKB layout(s) for Hyprland, before the user's ~/.config/hypr/input.lua
          (which can change it). The NixOS module passes the system's
          `services.xserver.xkb.layout`. Null: upstream's default ("us", or
          XKBLAYOUT from /etc/vconsole.conf, which NixOS doesn't write).
        '';
      };
      variant = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "XKB variant(s) for `omarchy.keyboard.layout`.";
      };
    };

    keybinds = mkOption {
      type = types.attrsOf bindType;
      default = { };
      example = lib.literalExpression ''
        {
          "SUPER + SHIFT + G".launch = "discord";
          "SUPER + SHIFT + SLASH".launch = "bitwarden";
          "SUPER + SHIFT + X".enable = false;
          "SUPER + ALT + D" = { description = "Docs"; webapp = "https://nixos.org/manual"; };
          "SUPER + SHIFT + LEFT".lua = "hl.dsp.window.move({ direction = \"l\" })";
        }
      '';
      description = ''
        Keybinds on top of Omarchy's defaults, keyed by Hyprland key combo
        as Omarchy writes them ("SUPER + SHIFT + B"). An entry replaces the
        default bind on that combo; `enable = false` removes it.
      '';
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    (lib.mkIf cfg.hyprland.enable {
      xdg.configFile."hypr/hyprland.lua".text = hyprlandLua;
    })

    # Upstream's per-user files (config/hypr), the user's own from the
    # first activation on (seed.nix): the menu opens them and Omarchy's
    # tools write to them (the monitor scale). A copy the user made in
    # ~/.local/state/hypr, which hyprland.lua's search path loads first,
    # moves here while this one is still the default.
    {
      omarchy.seededFiles = lib.genAttrs [ ".config/hypr/hyprsunset.conf" ]
        (_: { source = inputs.omarchy + "/config/hypr/hyprsunset.conf"; });
    }
    (lib.mkIf cfg.hyprland.enable {
      omarchy.seededFiles = lib.listToAttrs (map (name: lib.nameValuePair ".config/hypr/${name}" {
        source = inputs.omarchy + "/config/hypr/${name}";
        legacy = ".local/state/hypr/${name}";
      }) [ "monitors.lua" "input.lua" "bindings.lua" "looknfeel.lua" "autostart.lua" ]);
    })
  ]);
}
