# The essentials: the apps Omarchy's core features launch, and the defaults
# that tie them in: foot (terminal), Chromium (browser; web apps need a
# Chromium-based one), Nautilus (files), Neovim (editor), the viewers its
# MIME defaults open, the system tools its menu and binds call, the fonts,
# and the GTK look (PACKAGES.md groups 1 and 2). The CLI setup, TUI
# launchers, Omarchy's ecosystem and the agents are catalog.nix.
{ inputs }:
{ config, lib, pkgs, omarchyTools, ... }:
let
  cfg = config.omarchy;
  inherit (lib) mkOption types;

  omarchyPath = "${config.home.homeDirectory}/.local/share/omarchy";

  # Chromium with Omarchy's flags (config/chromium-flags.conf; nixpkgs'
  # wrapper doesn't read that file) and its extensions, loaded from the
  # stable OMARCHY_PATH (they carry manifest keys, so their IDs are fixed).
  # The desktop file is renamed to chromium.desktop, the ID Omarchy's
  # commands and MIME defaults use.
  chromiumFlags = lib.filter (l: l != "" && !lib.hasPrefix "--load-extension" l)
    (lib.splitString "\n" (builtins.readFile (inputs.omarchy + "/config/chromium-flags.conf")));
  chromiumWrapped = pkgs.chromium.override {
    commandLineArgs = chromiumFlags ++ [
      "--load-extension=${omarchyPath}/default/chromium/extensions/copy-url,${omarchyPath}/default/chromium/extensions/whatsapp-slim"
    ];
  };
  chromium = pkgs.symlinkJoin {
    name = "chromium-omarchy";
    paths = [ chromiumWrapped ];
    postBuild = ''
      rm -r $out/share/applications
      mkdir $out/share/applications
      cp ${chromiumWrapped}/share/applications/chromium-browser.desktop $out/share/applications/chromium.desktop
    '';
  };

  # A package with upstream's desktop entry (applications/<file>) in place
  # of its own: foot's carries the X-TerminalArg* keys xdg-terminal-exec
  # needs, imv's and mpv's Omarchy's names and flags.
  withLauncher = pkg: file: pkgs.symlinkJoin {
    name = "${lib.getName pkg}-omarchy";
    paths = [ pkg ];
    postBuild = ''
      rm -f $out/share/applications/${file}
      cp ${inputs.omarchy}/applications/${file} $out/share/applications/${file}
      icon=${inputs.omarchy}/applications/icons/${lib.removeSuffix ".desktop" file}.png
      if [ -e "$icon" ]; then
        mkdir -p $out/share/icons/hicolor/256x256/apps
        cp "$icon" $out/share/icons/hicolor/256x256/apps/
      fi
    '';
  };

  # Neovim with what LazyVim (omarchy-nvim) calls: git for lazy.nvim, a C
  # compiler and tree-sitter for parsers, the pickers' search tools, and
  # node for Mason's language servers (their binaries run through nix-ld,
  # which the NixOS module enables).
  neovim = pkgs.symlinkJoin {
    name = "neovim-omarchy";
    paths = [ pkgs.neovim ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/nvim --suffix PATH : ${lib.makeBinPath (with pkgs; [
        git gcc gnumake tree-sitter ripgrep fd fzf curl unzip gzip nodejs lazygit
      ])}
    '';
  };

  defaultApps = with pkgs; [
    # Defaults the keybinds launch.
    (withLauncher foot "foot.desktop") chromium nautilus neovim
    # Viewers (the MIME defaults) and system tools.
    (withLauncher imv "imv.desktop")
    (withLauncher (mpv.override { scripts = [ mpvScripts.mpris ]; }) "mpv.desktop")
    evince btop fastfetch gnome-disk-utility libsecret
  ];

  # The theme's icon color (Yaru-<color>), as omarchy-theme-set-gnome
  # applies it.
  iconsFile = cfg.theme.dir + "/icons.theme";
  iconTheme = if builtins.pathExists iconsFile
    then lib.trim (builtins.readFile iconsFile)
    else "Yaru-blue";
in
{
  options.omarchy = {
    configs.neovim.enable = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Seed ~/.config/nvim with Omarchy's LazyVim config (omarchy-nvim),
        themed by the current Omarchy theme, when there's no Neovim config
        yet. lazy.nvim installs the plugins on first start.
      '';
    };

    defaultApps = mkOption {
      type = types.listOf types.package;
      default = defaultApps;
      defaultText = lib.literalMD "foot, Chromium, Nautilus, Neovim, imv, mpv, Evince, btop, fastfetch, GNOME Disks";
      description = ''
        The default apps Omarchy's core features launch: terminal, browser,
        file manager, editor, the viewers its MIME defaults open, and the
        system tools its menu and binds call. Replace or filter the list to
        swap one out, e.g.
        `lib.filter (p: lib.getName p != "evince") options.omarchy.defaultApps.default`.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Low priority: a host's own package providing the same command (tealdeer's
    # tldr, its own neovim, …) wins instead of colliding.
    home.packages = map lib.lowPrio (cfg.defaultApps ++ (with pkgs; [
      # Fonts: Omarchy's monospace and its fallbacks (default/fontconfig).
      nerd-fonts.jetbrains-mono liberation_ttf noto-fonts noto-fonts-cjk-sans
      noto-fonts-color-emoji font-awesome
      # The GTK look: Adwaita(-dark) with Yaru icons in the theme's color.
      gnome-themes-extra yaru-theme
    ]));
    fonts.fontconfig.enable = true;
    xdg.configFile."fontconfig/conf.d/50-omarchy.conf".source =
      inputs.omarchy + "/default/fontconfig/conf.avail/50-omarchy.conf";

    # Session defaults (upstream's default/uwsm/default), for the session
    # and for shells: NixOS exports EDITOR=nano, and upstream's envs only
    # set theirs when EDITOR is empty.
    systemd.user.sessionVariables = {
      TERMINAL = lib.mkDefault "xdg-terminal-exec";
      EDITOR = lib.mkDefault "omarchy-launch-editor --inline";
    };
    home.sessionVariables = {
      TERMINAL = lib.mkDefault "xdg-terminal-exec";
      EDITOR = lib.mkDefault "omarchy-launch-editor --inline";
    };

    # omarchy-theme-set-gnome, applied on every activation from the active
    # theme. Defaults, so host theming (Stylix, gtk.*) wins.
    dconf.settings."org/gnome/desktop/interface" = lib.mapAttrs (_: lib.mkDefault) {
      color-scheme = if cfg.theme.mode == "light" then "prefer-light" else "prefer-dark";
      gtk-theme = if cfg.theme.mode == "light" then "Adwaita" else "Adwaita-dark";
      icon-theme = iconTheme;
      gtk-enable-primary-paste = true;
    };

    # Nautilus extensions (send with LocalSend, transcode).
    xdg.dataFile."nautilus-python/extensions".source =
      inputs.omarchy + "/default/nautilus-python/extensions";

    # Omarchy's Neovim config (omarchy-nvim), seeded once as upstream's
    # omarchy-nvim-setup does: a writable copy (lazy.nvim and the user edit
    # it), with the theme linked to the current Omarchy theme. An existing
    # ~/.config/nvim is left alone.
    home.activation.omarchyNeovim = lib.mkIf cfg.configs.neovim.enable
      (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        nvim="$HOME/.config/nvim"
        if [ ! -e "$nvim" ]; then
          run cp -r ${omarchyTools.omarchy-nvim}/share/omarchy-nvim/config "$nvim"
          run chmod -R u+w "$nvim"
          run mkdir -p "$nvim/lua/plugins"
          run ln -snf ../../../../.local/state/omarchy/current/theme/neovim.lua "$nvim/lua/plugins/theme.lua"
        fi
      '');

    # Omarchy's passwordless default keyring (install/user/default-keyring.sh):
    # apps store secrets without a second password prompt after login.
    home.activation.omarchyKeyring = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${pkgs.bash}/bin/bash ${inputs.omarchy}/install/user/default-keyring.sh
    '';
  };
}
