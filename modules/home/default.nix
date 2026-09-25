# The Omarchy desktop, Home Manager side: Omarchy's Quickshell shell
# (bar and dropdown panels, menu, notifications, OSD, lock, idle, polkit,
# clipboard, wallpaper), the omarchy-* commands with their declarative NixOS
# versions installed on top, the theme hierarchy, and the NixOS menu layer.
{ inputs }:
{ config, lib, pkgs, ... }:
let
  cfg = config.omarchy;
  inherit (lib) mkOption types;

  # Stable OMARCHY_PATH: a symlink to the package's share/omarchy. Quickshell
  # identifies a running shell by its config path, so the shell and every
  # `omarchy-shell` IPC call must use the same path across rebuilds.
  omarchyPath = "${config.home.homeDirectory}/.local/share/omarchy";

  # Omarchy's shell needs Quickshell 0.3.1; 26.05 ships 0.3.0.
  unstable = import inputs.nixpkgs-unstable {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.allowUnfree = true;
  };
  quickshell = unstable.quickshell;

  # Omarchy's own tools (pkgs/tools): omasnap, ttfx, owe, elsewhen, …
  tools = import ../../pkgs/tools { inherit pkgs inputs; };

  # ---------------------------------------------------------------- themes
  # Every theme (Omarchy's built-in set + installed community themes) run
  # through Omarchy's own renderer, exactly as omarchy-theme-set stages one:
  # alacritty.toml → colors.toml for older themes, then every template in
  # default/themed/ (shell.toml, kitty.conf, neovim.lua, btop.theme, …)
  # that the theme doesn't ship itself.
  theme = import ../../lib/theme.nix { inherit (inputs) omarchy; inherit (cfg) stateDir; };
  # Rendering needs only upstream's renderer; the NixOS command layer
  # (which carries the themes tree in its environment) would be circular.
  omarchyUpstream = pkgs.callPackage ../../pkgs/omarchy.nix { src = inputs.omarchy; };
  themeDir = name: t: pkgs.runCommand "omarchy-theme-${name}" {
    nativeBuildInputs = [ omarchyUpstream pkgs.gawk pkgs.gnused pkgs.coreutils pkgs.findutils ];
  } ''
    export HOME=$TMPDIR OMARCHY_PATH=${omarchyUpstream}/share/omarchy
    next=$HOME/.local/state/omarchy/current/next-theme
    mkdir -p "$(dirname "$next")"
    cp -r --no-preserve=mode ${t.dir} "$next"
    omarchy-theme-colors-from-alacritty "$next"
    omarchy-theme-set-templates
    cp -r "$next" $out
  '';
  themeDirs = lib.mapAttrs themeDir theme.all;
  themesTree = pkgs.linkFarm "omarchy-themes"
    (lib.mapAttrsToList (name: path: { inherit name path; }) themeDirs);
  currentTheme = themeDirs.${theme.name};

  # The NixOS layer over Omarchy's menu.
  menuExtension = import ../../lib/menu.nix { inherit lib; inherit (inputs) omarchy; };

  # ------------------------------------------------------ dev environments
  # nix-templates/dev + local framework layers (Install > Development),
  # baked into the store so scaffolding is a plain copy: no flake
  # evaluation, works offline. One dir per template plus index.tsv
  # (name<TAB>description) for the picker.
  devTemplates = import ../../lib/dev-templates.nix {
    inherit lib;
    src = inputs.dev-templates;
    local = ../../templates;
  };
  # Framework layers are copied over their upstream base, so they ship the
  # same .nvim.lua / .vscode / .editorconfig as the language they build on.
  templateDir = name: t:
    if t ? base then
      pkgs.runCommand "dev-template-${name}" { } ''
        mkdir $out
        cp -r --no-preserve=mode ${t.base}/. ${t.path}/. $out/
      ''
    else t.path;
  devTemplatesDir = pkgs.linkFarm "omarchy-dev-templates" (
    lib.mapAttrsToList (name: t: { inherit name; path = templateDir name t; }) devTemplates.all
    ++ [{
      name = "index.tsv";
      path = pkgs.writeText "dev-templates-index.tsv" (lib.concatStrings
        (lib.mapAttrsToList (name: t: "${name}\t${t.description}\n") devTemplates.templates));
    }]
  );

  # -------------------------------------------------------------- commands
  # NixOS versions of Omarchy commands (bin/), installed over upstream's in
  # the package. Anything they call by bare name (omarchy-*, hyprctl,
  # systemctl, nix, sudo, …) resolves through the session PATH.
  command = name: deps: pkgs.writeShellApplication {
    inherit name;
    runtimeInputs = deps;
    runtimeEnv = {
      OMARCHY_STATE = cfg.stateDirPath;
      OMARCHY_CONFIG = cfg.configDir;
      OMARCHY_DEV_TEMPLATES = devTemplatesDir;
      OMARCHY_COMMUNITY_THEMES = ../../data/community-themes.json;
      OMARCHY_THEMES = themesTree;
      OMARCHY_AGENTS = cfg.catalogFiles.agents;
    };
    text = builtins.readFile ../../bin/${name + ".sh"};
  };
  # The one rebuild every declarative action funnels through, generated
  # from the host's rebuild command.
  rebuild = pkgs.writeShellApplication {
    name = "omarchy-nixos-rebuild";
    text = ''
      echo ":: Rebuilding NixOS..."
      ${cfg.rebuildCommand}
      echo ":: Done."
    '';
  };
  replacements = [
    rebuild
    (command "omarchy-restart-shell"          [ ])
    (command "omarchy-launch-shell"           [ ])
    (command "omarchy-apply-lock"             [ ])
    (command "omarchy-provision-first-run"    [ ])
    (command "omarchy-update-available"       [ ])
    (command "omarchy-dns"                    [ pkgs.libnotify ])
    (command "omarchy-update"                 [ pkgs.gum pkgs.git pkgs.coreutils ])
    (command "omarchy-pkg-install"            [ pkgs.gum pkgs.jq pkgs.fzf pkgs.coreutils ])
    (command "omarchy-pkg-remove"             [ pkgs.gum pkgs.jq pkgs.coreutils ])
    (command "omarchy-pkg-present"            [ pkgs.jq ])
    (command "omarchy-pkg-missing"            [ ])
    (command "omarchy-pkg-attr"               [ ])
    (command "omarchy-pkg-add"                [ ])
    (command "omarchy-pkg-aur-add"            [ ])
    (command "omarchy-pkg-drop"               [ ])
    (command "omarchy-install-browser"        [ ])
    (command "omarchy-default-agent"          [ pkgs.jq pkgs.git pkgs.coreutils ])
    (command "omarchy-theme-set-browser"      [ pkgs.procps ])
    (command "omarchy-theme-set"              [ pkgs.jq pkgs.coreutils ])
    (command "omarchy-theme-install"          [ pkgs.jq pkgs.gnused pkgs.coreutils ])
    (command "omarchy-theme-remove"           [ pkgs.jq pkgs.coreutils ])
    (command "omarchy-dev-env"                [ pkgs.gum pkgs.coreutils ])
    (command "omarchy-install-dev-env"        [ ])
    (command "omarchy-install-docker-dbs"     [ pkgs.jq pkgs.coreutils ])
    (command "omarchy-install-font"           [ pkgs.fontconfig ])
    (command "omarchy-remove-launcher-entry"  [ pkgs.jq pkgs.gnugrep pkgs.coreutils pkgs.desktop-file-utils ])
  ];
  omarchy = pkgs.callPackage ../../pkgs/omarchy.nix {
    src = inputs.omarchy;
    inherit replacements;
    plugins = [ tools.elsewhen ];
  };

  # Programs Omarchy's shell and commands call by name. The services behind
  # them (NetworkManager, BlueZ, PipeWire, UPower, power-profiles-daemon,
  # polkit, uwsm) come from the NixOS module.
  runtimeDeps = with pkgs; [
    quickshell
    # Hyprland tools match the compositor, which comes from unstable too.
    unstable.hyprpicker unstable.hyprsunset unstable.hyprland-preview-share-picker
    # Omarchy's own: screenshots, the screensaver, video wallpapers.
    tools.omasnap tools.ttfx tools.owe
    gum jq fzf curl socat perl python3 bc file
    wl-clipboard wtype inotify-tools libnotify desktop-file-utils
    udiskie                     # automount, launched by Omarchy's autostart
    satty grim slurp tesseract zbar
    gpu-screen-recorder ffmpeg ffmpegthumbnailer vips imagemagick
    brightnessctl ddcutil iw qrencode xdg-terminal-exec xdg-utils gtk3
    fastfetch localsend playerctl pulseaudio pamixer alsa-utils
    dosfstools exfatprogs
    procps util-linux libxkbcommon
  ];

  # Menu-managed packages (Install > Package appends here, Remove > Package
  # deletes). Unknown attribute names are skipped with a warning instead of
  # failing the build, so a typo'd entry can never brick a rebuild.
  appState = builtins.fromJSON (builtins.readFile (cfg.stateDir + "/apps.json"));
  resolvePackage = name:
    let path = lib.splitString "." name; in
    if lib.hasAttrByPath path pkgs
    then [ (lib.getAttrFromPath path pkgs) ]
    else lib.warn "omarchy: unknown package '${name}' in apps.json — skipped" [ ];
  menuPackages = lib.concatMap resolvePackage appState.packages;
in
{
  imports = [
    (import ./hyprland.nix { inherit inputs; })
    (import ./apps.nix { inherit inputs; })
    (import ./catalog.nix { inherit inputs; })
    (import ./shell.nix { inherit inputs; })
  ];

  options.omarchy = {
    enable = lib.mkEnableOption ''
      the Omarchy desktop: Omarchy's Quickshell shell (bar and dropdown
      panels for network, bluetooth, audio, display, power and stats,
      calendar, weather, tailscale; the Omarchy menu; notifications, OSD,
      lock screen, idle, polkit agent, clipboard history, wallpaper), its
      commands and themes. Needs Hyprland 0.55+ (the Lua config API) and the
      omarchy NixOS module'';

    stateDir = mkOption {
      type = types.path;
      example = lib.literalExpression "./omarchy";
      description = ''
        Directory in the host's config holding the state the menu edits:
        apps.json (menu-installed packages), theme.json (active theme and
        installed community themes) and dbs.json (development databases).
        Read at build time.
      '';
    };

    stateDirPath = mkOption {
      type = types.str;
      example = "/home/me/nixos/omarchy";
      description = ''
        Where `stateDir` lives on this machine, as a writable path: the
        menu's install, theme and database commands edit the JSON files
        there and rebuild.
      '';
    };

    configDir = mkOption {
      type = types.str;
      example = "/home/me/nixos";
      description = ''
        The host's NixOS config (flake) on this machine. The menu opens it
        for editing (Setup > Config, keybindings, monitors), and
        Update > Everything runs `nix flake update` in it.
      '';
    };

    rebuildCommand = mkOption {
      type = types.str;
      default = "sudo nixos-rebuild switch --flake /etc/nixos";
      description = "Command the menu runs to apply changes.";
    };

    package = mkOption {
      type = types.package;
      readOnly = true;
      default = omarchy;
      description = "The Omarchy package with the NixOS command layer (share/omarchy is OMARCHY_PATH).";
    };

    theme = mkOption {
      type = types.attrs;
      readOnly = true;
      default = theme;
      description = ''
        The active theme, resolved from theme.json: `name`, `mode`
        ("dark"/"light"), `palette` (Omarchy's color keys, bare hex),
        `colors` (a derived palette), `ansi` (16 colors) and `wallpaper`.
        For host config that themes other programs (Stylix, …).
      '';
    };

    themes = mkOption {
      type = types.package;
      readOnly = true;
      default = themesTree;
      description = "Every theme, rendered: one directory per theme.";
    };

    currentTheme = mkOption {
      type = types.package;
      readOnly = true;
      default = currentTheme;
      description = "The active theme's rendered directory.";
    };

    devTemplates = mkOption {
      type = types.package;
      readOnly = true;
      default = devTemplatesDir;
      description = "Every dev-environment template (one directory each) plus index.tsv.";
    };
  };

  config = lib.mkMerge [
  # nixos-unstable, for the modules here that need its packages (catalog.nix).
  { _module.args.omarchyUnstable = unstable; }
  # Omarchy's own tools, for catalog.nix.
  { _module.args.omarchyTools = tools; }

  (lib.mkIf cfg.enable {
    home.packages = [ omarchy ] ++ runtimeDeps ++ menuPackages;

    home.file.".local/share/omarchy".source = "${omarchy}/share/omarchy";
    # The `omarchy` icon font the menu and bar glyphs use.
    home.file.".local/share/fonts/omarchy.ttf".source =
      "${omarchy}/share/omarchy/default/fonts/omarchy/omarchy.ttf";

    home.sessionVariables.OMARCHY_PATH = omarchyPath;
    systemd.user.sessionVariables.OMARCHY_PATH = omarchyPath;

    # Theme hierarchy, as Omarchy lays it out: every theme under
    # ~/.config/omarchy/themes/<name>/, the active one at
    # ~/.local/state/omarchy/current/theme (colors.toml + shell.toml for
    # the shell, neovim.lua, kitty.conf, backgrounds, …).
    xdg.configFile."omarchy/themes".source = themesTree;
    home.file.".local/state/omarchy/current/theme".source = currentTheme;
    home.file.".local/state/omarchy/current/theme.name".text = theme.name;

    # current/background: the wallpaper link the shell (and omarchy-theme-
    # bg-set) use. Reset to the theme's first background when the theme
    # changes or the link went stale; a background picked within the same
    # theme survives rebuilds.
    home.activation.omarchyBackground = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      state="$HOME/.local/state/omarchy/current"
      stamp="$state/background.theme"
      if [ "$(cat "$stamp" 2>/dev/null)" != ${lib.escapeShellArg theme.name} ] || [ ! -e "$state/background" ]; then
        run ln -sfn "$HOME/${theme.wallpaper}" "$state/background"
        run sh -c 'echo "$1" >"$2"' _ ${lib.escapeShellArg theme.name} "$stamp"
      fi
    '';

    # Omarchy's desktop configs next to hyprland.lua: screen sharing through
    # the preview picker, the night light's schedule. Below mkDefault, so
    # the host's own files win.
    xdg.configFile."hypr/xdph.conf".source =
      lib.mkOverride 1100 (inputs.omarchy + "/config/hypr/xdph.conf");
    xdg.configFile."hypr/hyprsunset.conf".source =
      lib.mkOverride 1100 (inputs.omarchy + "/config/hypr/hyprsunset.conf");
    xdg.configFile."hyprland-preview-share-picker/config.yaml".source =
      lib.mkOverride 1100 (inputs.omarchy + "/config/hyprland-preview-share-picker/config.yaml");

    # OWE, Omarchy's wallpaper engine: video backgrounds on the desktop
    # (stills are the shell's), and the frames its lock-screen feed shows.
    systemd.user.services.owed = {
      Unit = {
        Description = "OWE wallpaper engine daemon";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${tools.owe}/bin/owed";
        Restart = "on-failure";
        RestartSec = 2;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    # The NixOS layer over Omarchy's menu (install/remove via apps.json,
    # NixOS update actions, Arch-only entries hidden).
    xdg.configFile."omarchy/extensions/omarchy-menu.jsonc".text = menuExtension;

    # Branding the About screen and screensaver render; seeded from
    # Omarchy's logo once, then editable from Style > About / Screensaver.
    home.activation.omarchyBranding = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      dir="$HOME/.config/omarchy/branding"
      run mkdir -p "$dir"
      for f in about.txt screensaver.txt; do
        [ -e "$dir/$f" ] || run install -m644 ${omarchy}/share/omarchy/logo.txt "$dir/$f"
      done
    '';

    # The shell, supervised by systemd instead of upstream's
    # omarchy-launch-shell loop. The unit embeds the package and the
    # current theme, so a rebuild that changes either restarts it (the
    # shell reads theme colors at startup).
    systemd.user.services.omarchy-shell = {
      Unit = {
        Description = "Omarchy shell (Quickshell)";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
        X-Restart-Triggers = [ "${omarchy}" "${currentTheme}" ];
      };
      Service = {
        ExecStart = "${quickshell}/bin/quickshell -n -p ${omarchyPath}/shell";
        Environment = [
          "OMARCHY_PATH=${omarchyPath}"
          "QS_DISABLE_FILE_WATCHER=1"
          "QS_NO_RELOAD_POPUP=1"
          # Theme backgrounds are mostly WebP; nixpkgs' Quickshell only
          # ships Qt's built-in image formats (the wrapper prepends its own
          # plugin paths, so this one is kept).
          "QT_PLUGIN_PATH=${unstable.kdePackages.qtimageformats}/lib/qt-6/plugins"
          # OWE's lock-screen feed (Owe.LockFeed), which the lock screen
          # loads when it's there.
          "QML_IMPORT_PATH=${tools.owe-lockfeed}/lib/qt6/qml"
          "PATH=${config.home.profileDirectory}/bin:/run/wrappers/bin:/run/current-system/sw/bin"
        ];
        Restart = "on-failure";
        RestartSec = 1;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  })
  ];
}
