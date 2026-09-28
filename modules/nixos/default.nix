# The Omarchy desktop, NixOS side: the system services Omarchy's shell and
# commands rely on, the lock screen's PAM services, Omarchy's login screen
# and Plymouth splash, the development databases the menu toggles, and (with
# Home Manager's NixOS module imported) the desktop itself for each user in
# `omarchy.users`.
{ inputs, homeManagerModules }:
{ config, lib, pkgs, options, ... }:
let
  cfg = config.omarchy;
  inherit (lib) mkDefault mkOption types;

  unstable = import inputs.nixpkgs-unstable {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.allowUnfree = true;
  };

  # branding.json in the state directory (optional; Style > Branding writes it).
  brandingState = let f = cfg.stateDir + "/branding.json"; in
    if builtins.pathExists f then f else builtins.toFile "branding.json" "{}";

  # Development databases (Install > Development > Docker DB). The menu
  # edits dbs.json and rebuilds, so each container is a declarative
  # virtualisation.oci-containers unit instead of upstream's loose
  # `docker run`. Images, ports and credentials mirror upstream
  # (dev-friendly: empty/known passwords, bound to localhost only).
  dbState = builtins.fromJSON (builtins.readFile (cfg.stateDir + "/dbs.json"));
  dbDefs = {
    mysql = {
      image = "mysql:8.4";
      ports = [ "127.0.0.1:3306:3306" ];
      environment = {
        MYSQL_ROOT_PASSWORD = "";
        MYSQL_ALLOW_EMPTY_PASSWORD = "true";
      };
      volumes = [ "omarchy-mysql:/var/lib/mysql" ];
    };
    mariadb = {
      image = "mariadb:11.8";
      ports = [ "127.0.0.1:3306:3306" ];
      environment = {
        MARIADB_ROOT_PASSWORD = "";
        MARIADB_ALLOW_EMPTY_ROOT_PASSWORD = "true";
      };
      volumes = [ "omarchy-mariadb:/var/lib/mysql" ];
    };
    postgres = {
      image = "postgres:18";
      ports = [ "127.0.0.1:5432:5432" ];
      environment.POSTGRES_HOST_AUTH_METHOD = "trust";
      volumes = [ "omarchy-postgres:/var/lib/postgresql" ];
    };
    redis = {
      image = "redis:7";
      ports = [ "127.0.0.1:6379:6379" ];
      volumes = [ "omarchy-redis:/data" ];
    };
    mongodb = {
      image = "mongo:noble";
      ports = [ "127.0.0.1:27017:27017" ];
      environment = {
        MONGO_INITDB_ROOT_USERNAME = "admin";
        MONGO_INITDB_ROOT_PASSWORD = "admin123";
      };
      volumes = [ "omarchy-mongodb:/data/db" ];
    };
    # Upstream image is x86_64-only; the picker hides it elsewhere.
    mssql = {
      image = "mcr.microsoft.com/mssql/server:2022-CU12-ubuntu-22.04";
      ports = [ "127.0.0.1:1433:1433" ];
      environment = {
        MSSQL_PID = "Developer";
        ACCEPT_EULA = "Y";
        MSSQL_SA_PASSWORD = "@dmin123";
      };
      volumes = [ "omarchy-mssql:/var/opt/mssql" ];
    };
  };
  enabledDbs = lib.filter (n: dbDefs ? ${n}) dbState.enabled;

  # The name the boot splash and login screen show (Style > Branding sets it
  # in the host's branding.json); anything but Omarchy gets a wordmark
  # drawn like Omarchy's.
  branding = if cfg.branding.name == "Omarchy" then null
    else pkgs.callPackage ../../pkgs/branding.nix { inherit (cfg.branding) name; };
  brandLogo = dir: lib.optionalString (branding != null) "cp ${branding}/logo.png ${dir}/logo.png";

  # Omarchy's Plymouth theme, with its /usr/share paths pointed at the store.
  plymouthTheme = pkgs.runCommand "omarchy-plymouth-theme" { } ''
    dir=$out/share/plymouth/themes/omarchy
    mkdir -p $dir
    cp -r ${inputs.omarchy}/default/plymouth/. $dir/
    chmod -R u+w $dir
    ${brandLogo "$dir"}
    substituteInPlace $dir/omarchy.plymouth \
      --replace-fail /usr/share/plymouth/themes/omarchy $dir
  '';

  # Omarchy's SDDM theme. It preselects the session whose name contains
  # "uwsm"; NixOS names it "Hyprland (UWSM)", so compare case-insensitively.
  # It has no user field and logs in as SDDM's last user, which Omarchy's
  # ISO seeds; before anyone has logged in that's empty, so fall back to the
  # first of `omarchy.users`.
  sddmTheme = pkgs.runCommand "omarchy-sddm-theme" { } ''
    dir=$out/share/sddm/themes/omarchy
    mkdir -p $dir
    cp -r ${inputs.omarchy}/default/sddm/omarchy/. $dir/
    chmod -R u+w $dir
    ${brandLogo "$dir"}
    substituteInPlace $dir/Main.qml \
      --replace-fail 'name.indexOf("uwsm")' 'name.toLowerCase().indexOf("uwsm")' \
      --replace-fail 'property string currentUser: userModel.lastUser' \
        'property string currentUser: userModel.lastUser || ${builtins.toJSON (lib.head (cfg.users ++ [ "" ]))}'
  '';
  # The greeter runs in its own minimal Hyprland, as upstream's sddm.conf.d.
  greeterConfig = "${inputs.omarchy}/default/sddm/hyprland.lua";

  hasHomeManager = options ? home-manager.users;

  # A display manager the host already runs; Omarchy's login stays out of
  # its way.
  otherDisplayManager = config.services.greetd.enable
    || config.services.displayManager.gdm.enable or false
    || config.services.xserver.displayManager.lightdm.enable;

  # /usr/share/omarchy: the first desktop user's package (it carries their
  # menu layer and branding), else upstream's as this flake packages it.
  firstUser = lib.findFirst (u: cfg.homeManager.enable && hasHomeManager
    && config.home-manager.users ? ${u} && config.home-manager.users.${u}.omarchy.enable or false) null cfg.users;
  usrShareOmarchy = if firstUser != null then config.home-manager.users.${firstUser}.omarchy.package
    else pkgs.callPackage ../../pkgs/omarchy.nix { src = inputs.omarchy; };

  # /usr/share/fonts as on Arch (share/fonts/<family>/…): the system's
  # fonts and the first desktop user's (Omarchy's come with Home Manager).
  usrShareFonts = pkgs.buildEnv {
    name = "omarchy-usr-share-fonts";
    paths = config.fonts.packages
      ++ lib.optional (firstUser != null) config.home-manager.users.${firstUser}.home.path;
    pathsToLink = [ "/share/fonts" ];
  };

  # The active theme, for the browser color policy.
  theme = import ../../lib/theme.nix { inherit (inputs) omarchy; inherit (cfg) stateDir; };
in
{
  options.omarchy = {
    enable = lib.mkEnableOption "the system side of the Omarchy desktop";

    stateDir = mkOption {
      type = types.path;
      example = lib.literalExpression "./omarchy";
      description = ''
        The same state directory as the Home Manager module's
        `omarchy.stateDir`; the NixOS side reads dbs.json from it.
      '';
    };

    users = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Users running Omarchy. They join the docker group (development
        databases), and with Home Manager's NixOS module imported each gets
        the desktop (see `omarchy.homeManager.enable`).
      '';
    };

    configDir = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "/home/me/nixos";
      description = ''
        This machine's NixOS flake, as a path on disk the users can write
        (the menu edits the state files in it and rebuilds from it). Passed
        to each user's desktop as `omarchy.configDir`.
      '';
    };

    stateDirPath = mkOption {
      type = types.nullOr types.str;
      default = if cfg.configDir == null then null else "${cfg.configDir}/omarchy";
      defaultText = lib.literalExpression ''"''${config.omarchy.configDir}/omarchy"'';
      description = ''
        Where `stateDir` lives on disk, writable; passed to each user's
        desktop. The default assumes the state directory is `omarchy/` at the
        root of `configDir`, as in the host template.
      '';
    };

    rebuildCommand = mkOption {
      type = types.nullOr types.str;
      default = if cfg.configDir == null then null else "sudo nixos-rebuild switch --flake ${cfg.configDir}";
      defaultText = lib.literalExpression ''"sudo nixos-rebuild switch --flake ''${config.omarchy.configDir}"'';
      description = "How the menu applies changes; passed to each user's desktop.";
    };

    branding.name = mkOption {
      type = types.str;
      default = (lib.importJSON brandingState).name or "Omarchy";
      defaultText = lib.literalExpression ''"name" from branding.json in stateDir, else "Omarchy"'';
      example = "Willexander";
      description = ''
        The name on the boot splash and login screen (a wordmark in
        Omarchy's style), the screensaver and the About screen. The menu's
        Style > Branding writes it to branding.json in the state directory.
        Passed to each user's desktop.
      '';
    };

    homeManager.enable = mkOption {
      type = types.bool;
      default = hasHomeManager;
      defaultText = lib.literalExpression "true when Home Manager's NixOS module is imported";
      description = ''
        Give every user in `omarchy.users` the desktop through Home Manager:
        imports this flake's Home Manager module for them and enables it with
        this module's state directory, config directory and rebuild command
        (as defaults, so a user's own Home Manager config can override them).
      '';
    };

    ecosystem.enable = lib.mkEnableOption ''
      Omarchy's whole ecosystem on top of the defaults ("Install entire
      ecosystem"): its apps, web apps and development tools with their
      keybinds (each user's Home Manager `omarchy.ecosystem.enable`, passed
      down as a default) and, on the system, Docker'';

    development.enable = mkOption {
      type = types.bool;
      default = cfg.ecosystem.enable;
      defaultText = lib.literalExpression "config.omarchy.ecosystem.enable";
      description = ''
        Docker for development, as Omarchy sets it up (users in
        `omarchy.users` join the docker group). Also on whenever a
        development database is enabled from the menu (dbs.json).
      '';
    };

    shell = mkOption {
      type = types.enum [ "zsh" "bash" ];
      default = "zsh";
      description = ''
        The login shell of the users in `omarchy.users`, with Omarchy's
        shell setup (each user's Home Manager `omarchy.shell`, passed down).
      '';
    };

    configs.git.enable = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Omarchy's git defaults (config/git/config upstream: aliases, rebase
        on pull, histogram diffs, rerere, …) in /etc/gitconfig, below every
        user's own git config.
      '';
    };

    printing.enable = mkOption {
      type = types.bool;
      default = true;
      description = "Printing, as Omarchy sets it up: CUPS, printer discovery (Avahi/mDNS) and system-config-printer.";
    };

    inputMethod.enable = mkOption {
      type = types.bool;
      default = true;
      description = "fcitx5 input methods (CJK and other non-Latin input), as Omarchy ships them.";
    };

    login = {
      enable = mkOption {
        type = types.bool;
        default = !otherDisplayManager;
        defaultText = lib.literalMD "`true`, unless the host enables greetd, GDM or LightDM";
        description = ''
          Omarchy's login screen: SDDM on Wayland, in a minimal Hyprland,
          with Omarchy's theme, starting the Hyprland (UWSM) session. Off to
          bring your own display manager.
        '';
      };
      autoLogin = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "me";
        description = ''
          Log this user straight in, as Omarchy does on an encrypted disk
          (the disk passphrase already proved who's there). The lock screen
          still guards the session.
        '';
      };
    };

    cursor = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          The pointer cursor theme on the login screen (SDDM and its
          Hyprland) and, passed down as defaults, in each user's desktop
          (Home Manager's `omarchy.cursor`: GTK, X11/XWayland, Hyprland).
        '';
      };
      package = mkOption {
        type = types.package;
        default = pkgs.bibata-cursors;
        defaultText = lib.literalExpression "pkgs.bibata-cursors";
        description = "Package providing the cursor theme (under share/icons).";
      };
      name = mkOption {
        type = types.str;
        default = "Bibata-Modern-Classic";
        description = "The cursor theme's name: its directory in the package's share/icons.";
      };
      size = mkOption {
        type = types.int;
        default = 24;
        description = "Cursor size (upstream Omarchy uses 24).";
      };
    };

    envfs.enable = mkOption {
      type = types.bool;
      default = true;
      description = ''
        NixOS's envfs (`services.envfs`) on /usr/bin and /bin: a path like
        /usr/bin/python3 or /usr/bin/omarchy-notification-send resolves to
        that command on the PATH of the process asking (for the shell's
        plugins: the omarchy-shell unit's PATH, which has the user's
        profile), so the shell plugins and scripts written for Arch that
        run /usr/bin/<cmd> or start with `#!/usr/bin/bash` work. A command
        that isn't on the caller's PATH stays missing (bash, sh and env are
        always there). About a third of the community's plugins need this.
      '';
    };

    usrShare.enable = mkOption {
      type = types.bool;
      default = true;
      description = ''
        /usr/share/omarchy (Omarchy's files, OMARCHY_PATH on Arch) and
        /usr/share/zoneinfo, as links (systemd-tmpfiles), for shell plugins
        that read them at those paths. /usr/share/omarchy is the first
        desktop user's Omarchy package (their menu layer and branding).
      '';
    };

    usrShare.voxtype = mkOption {
      type = types.bool;
      default = false;
      description = ''
        /usr/share/voxtype/quickshell: voxtype's shared Quickshell module
        (from nixos-unstable's voxtype source; nixpkgs doesn't install it),
        which voxtype plugins (Vox Portrait) import from that fixed path.
      '';
    };

    nixLd.enable = mkOption {
      type = types.bool;
      default = true;
      description = ''
        nix-ld (`programs.nix-ld`), so prebuilt glibc binaries run: the
        language servers and tools the editor and mise download, and the
        helpers community shell plugins ship or download (an mruby runtime,
        a PyInstaller bundle, a Node SEA, release binaries). Besides
        nix-ld's defaults it offers the libraries those were found to link:
        libevdev, PipeWire, PulseAudio, D-Bus, curl, OpenSSL, zlib, GLib,
        libxkbcommon, Wayland, libstdc++/libgcc_s. On by default: this
        desktop has always enabled nix-ld (for the editor's downloads), the
        libraries are ones the desktop already has, and a plugin added with
        `omarchy plugin add` runs unsandboxed in the shell anyway, so
        loading its binaries opens nothing new.
      '';
    };

    plugins = mkOption {
      type = types.attrsOf (import ../plugin-options.nix { inherit lib; });
      default = { };
      description = ''
        Omarchy shell plugins for every user in `omarchy.users` (passed to
        their Home Manager `omarchy.plugins`): by manifest id, with a
        source (`src`, or `url` + `rev` + `hash`) to install and switch
        one on, and `packages` it runs. See the Home Manager option.
      '';
    };

    plymouth.enable = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Omarchy's boot splash. It also draws the disk-unlock prompt, so a
        TPM PIN / LUKS passphrase is asked on a clean graphical screen. On
        NVIDIA, load the driver in the initrd (early KMS) or Plymouth falls
        back to text mode.
      '';
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [ {
    # Hyprland under uwsm, as Omarchy runs it. Omarchy tracks the newest
    # Hyprland (Arch ships it), and its Lua config uses APIs stable
    # releases don't have yet (e.g. monitor.reserved in qconsole.lua), so
    # the version comes from nixos-unstable, with its matching portal.
    programs.hyprland = {
      enable = mkDefault true;
      withUWSM = mkDefault true;
      package = mkDefault unstable.hyprland;
      portalPackage = mkDefault unstable.xdg-desktop-portal-hyprland;
    };

    # Services the shell's panels and commands talk to.
    networking.networkmanager.enable = mkDefault true; # network panel (NM backend only)
    hardware.bluetooth.enable = mkDefault true;         # bluetooth panel
    services.upower.enable = mkDefault true;            # power panel, battery
    services.power-profiles-daemon.enable = mkDefault true;
    security.polkit.enable = true;                      # the shell is the polkit agent
    security.rtkit.enable = mkDefault true;             # realtime audio for PipeWire
    services.pipewire = {
      enable = mkDefault true;
      pulse.enable = mkDefault true;                    # pactl, used by the audio commands
      wireplumber.enable = mkDefault true;
    };

    # The shell authenticates its lock screen through these PAM services and
    # refuses to lock when the password one is missing. Upstream writes
    # /etc/pam.d itself (omarchy-apply-lock).
    security.pam.services = {
      omarchy-lock-password = { };
      # As upstream's login/sddm.sh: the login password doesn't create an
      # encrypted keyring; the desktop seeds a passwordless default one.
      sddm.enableGnomeKeyring = lib.mkIf cfg.login.enable false;
    } // lib.optionalAttrs config.services.fprintd.enable {
      omarchy-lock-fingerprint = { fprintAuth = true; unixAuth = false; };
    };

    # Screen recording captures through KMS, which needs
    # gpu-screen-recorder's capability wrapper.
    programs.gpu-screen-recorder.enable = true;

    # Docker (the development layer) and the development databases.
    virtualisation.docker.enable = mkDefault (cfg.development.enable || enabledDbs != [ ]);
    virtualisation.oci-containers = lib.mkIf (enabledDbs != [ ]) {
      backend = "docker";
      containers = lib.genAttrs enabledDbs (name: dbDefs.${name});
    };
    users.users = lib.genAttrs cfg.users (_: {
      extraGroups = lib.optional config.virtualisation.docker.enable "docker";
      # Above NixOS's own mkDefault shell, below a host's plain setting.
      shell = lib.mkOverride 900 (if cfg.shell == "zsh" then pkgs.zsh else pkgs.bashInteractive);
    });
    programs.zsh.enable = lib.mkIf (cfg.shell == "zsh") (mkDefault true);

    # Omarchy's git defaults, system-wide so every user's own config wins.
    programs.git = lib.mkIf cfg.configs.git.enable {
      enable = mkDefault true;
      config.include.path = "${inputs.omarchy}/config/git/config";
    };
    # The time zone, when the config declares it: the menu's Timezone entry
    # (omarchy-menu-timezone) points there instead of calling timedatectl,
    # which NixOS refuses then.
    environment.etc."omarchy/time-zone" = lib.mkIf (config.time.timeZone != null) {
      text = config.time.timeZone;
    };

    environment.systemPackages = lib.optional cfg.login.enable sddmTheme
      # The cursor theme in /run/current-system/sw/share/icons, where the
      # login screen (and any other user) finds it.
      ++ lib.optional cfg.cursor.enable cfg.cursor.package;

    boot.plymouth = lib.mkIf cfg.plymouth.enable {
      enable = true;
      # Forced: Stylix (and other theming modules) set their own splash.
      theme = lib.mkForce "omarchy";
      themePackages = [ plymouthTheme ];
    };

    # The core apps' system side: Nautilus (gvfs mounts, sushi previews,
    # its Python extensions), the keyring, GTK settings, portals.
    services.gvfs.enable = mkDefault true;
    services.gnome.sushi.enable = mkDefault true;
    services.gnome.gnome-keyring.enable = mkDefault true;
    programs.dconf.enable = true;
    # The GNOME interface keys GTK apps read, as omarchy-theme-set-gnome sets
    # them for the theme (dark/light, GTK and icon theme) plus the cursor:
    # a system database without locks, so they're defaults a user's own
    # choice (a settings app, a live theme switch) overrides and keeps.
    programs.dconf.profiles.user.databases = [{
      settings."org/gnome/desktop/interface" = {
        color-scheme = if theme.mode == "light" then "prefer-light" else "prefer-dark";
        gtk-theme = if theme.mode == "light" then "Adwaita" else "Adwaita-dark";
        icon-theme = let f = theme.dir + "/icons.theme"; in
          if builtins.pathExists f then lib.trim (builtins.readFile f) else "Yaru-blue";
        gtk-enable-primary-paste = true;
      } // lib.optionalAttrs cfg.cursor.enable {
        cursor-theme = cfg.cursor.name;
        cursor-size = lib.gvariant.mkInt32 cfg.cursor.size;
      };
    }];
    environment.sessionVariables.NAUTILUS_4_EXTENSION_DIR =
      "${pkgs.nautilus-python}/lib/nautilus/extensions-4";
    xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];

    # Chromium-family browsers take the theme's color, as
    # omarchy-theme-set-browser writes it (a policy; applied on rebuild).
    programs.chromium = {
      enable = mkDefault true;
      extraOpts = {
        BrowserThemeColor = "#${theme.palette.background}";
        BrowserColorScheme = "device";
      };
    };

    # Networking as Omarchy runs it: systemd-resolved, no wait-online at
    # boot, a firewall that denies incoming except LocalSend.
    services.resolved.enable = mkDefault true;
    systemd.services.NetworkManager-wait-online.enable = mkDefault false;
    networking.firewall.enable = mkDefault true;
    programs.localsend = {
      enable = mkDefault true;
      openFirewall = mkDefault true;
    };

    # Prebuilt binaries the editor and dev tools download (Mason's language
    # servers, mise) and plugins ship, which expect a regular Linux loader
    # (omarchy.nixLd).
    programs.nix-ld = lib.mkIf cfg.nixLd.enable {
      enable = mkDefault true;
      libraries = options.programs.nix-ld.libraries.default ++ (with pkgs; [
        stdenv.cc.cc.lib zlib curl openssl dbus glib libevdev pipewire
        libpulseaudio libxkbcommon wayland
      ]);
    };

    # plocate's index, refreshed daily.
    services.locate = {
      enable = mkDefault true;
      package = mkDefault pkgs.plocate;
    };

    services.printing.enable = mkDefault cfg.printing.enable;
    services.avahi = lib.mkIf cfg.printing.enable {
      enable = mkDefault true;
      nssmdns4 = mkDefault true;
      openFirewall = mkDefault true;
    };
    services.system-config-printer.enable = mkDefault cfg.printing.enable;
    programs.system-config-printer.enable = mkDefault cfg.printing.enable;

    i18n.inputMethod = lib.mkIf cfg.inputMethod.enable {
      enable = true;
      type = "fcitx5";
      fcitx5.waylandFrontend = true;
      fcitx5.addons = [ pkgs.fcitx5-gtk pkgs.qt6Packages.fcitx5-configtool ];
    };

    # Login.
    services.displayManager = lib.mkIf cfg.login.enable {
      defaultSession = mkDefault "hyprland-uwsm";
      autoLogin = lib.mkIf (cfg.login.autoLogin != null) {
        enable = true;
        user = cfg.login.autoLogin;
      };
      sddm = {
        enable = mkDefault true;
        wayland.enable = true;
        theme = "omarchy";
        # The greeter's Hyprland draws the pointer: it takes the theme from
        # its environment (SDDM's CursorTheme reaches only the greeter).
        settings.Wayland.CompositorCommand =
          lib.optionalString cfg.cursor.enable
            "${pkgs.coreutils}/bin/env XCURSOR_THEME=${cfg.cursor.name} XCURSOR_SIZE=${toString cfg.cursor.size} HYPRCURSOR_THEME=${cfg.cursor.name} HYPRCURSOR_SIZE=${toString cfg.cursor.size} XCURSOR_PATH=${cfg.cursor.package}/share/icons:/run/current-system/sw/share/icons "
          + "${config.programs.hyprland.package}/bin/start-hyprland -- --config ${greeterConfig}";
        settings.Theme = lib.mkIf cfg.cursor.enable {
          CursorTheme = mkDefault cfg.cursor.name;
          CursorSize = mkDefault cfg.cursor.size;
        };
      };
    };

    # Shell plugins written for Arch: /usr/bin/<cmd> and #!/usr/bin/bash
    # through envfs, Omarchy's files at /usr/share/omarchy.
    services.envfs.enable = lib.mkIf cfg.envfs.enable (mkDefault true);
    # The fallback directory serves processes started with no PATH (a
    # plugin's Process with clearEnvironment execs /usr/bin/setsid,
    # /usr/bin/mkdir, …): bash, coreutils and setsid besides env and sh.
    services.envfs.extraFallbackPathCommands = lib.mkIf cfg.envfs.enable ''
      ln -s ${pkgs.bashInteractive}/bin/bash $out/bash
      for f in ${pkgs.coreutils}/bin/* ${pkgs.util-linux}/bin/setsid; do
        [ -e "$out/''${f##*/}" ] || ln -s "$f" "$out/''${f##*/}"
      done
    '';
    systemd.tmpfiles.rules = lib.mkIf cfg.usrShare.enable ([
      "d /usr/share 0755 root root -"
      "L+ /usr/share/omarchy - - - - ${usrShareOmarchy}/share/omarchy"
      "L+ /usr/share/zoneinfo - - - - /etc/zoneinfo"
      "L+ /usr/share/fonts - - - - ${usrShareFonts}/share/fonts"
      # Omarchy's logo where Arch's omarchy-settings installs it.
      "d /usr/share/pixmaps 0755 root root -"
      "L+ /usr/share/pixmaps/omarchy.png - - - - ${usrShareOmarchy}/share/omarchy/icon.png"
    ] ++ lib.optionals cfg.usrShare.voxtype [
      "d /usr/share/voxtype 0755 root root -"
      "L+ /usr/share/voxtype/quickshell - - - - ${unstable.voxtype.src}/quickshell"
    ]);

    assertions = [{
      assertion = cfg.homeManager.enable -> hasHomeManager;
      message = "omarchy.homeManager.enable needs Home Manager's NixOS module (home-manager.nixosModules.home-manager) imported.";
    }];
  }

  # The desktop for each user, through Home Manager.
  (lib.optionalAttrs hasHomeManager {
    home-manager.users = lib.mkIf cfg.homeManager.enable (lib.genAttrs cfg.users (_: {
      imports = [ homeManagerModules.default ];
      omarchy = {
        enable = mkDefault true;
        ecosystem.enable = mkDefault cfg.ecosystem.enable;
        # Only what's set, so a user's own definitions merge with them.
        plugins = lib.mapAttrs (_: p: lib.filterAttrs (n: v: v != null && v != [ ] && v != { } && v != ""
          && !(n == "registry" && v)) p) cfg.plugins;
        # Compositor plugins are built against the Hyprland the system runs.
        hyprland.package = mkDefault config.programs.hyprland.package;
        shell = mkDefault cfg.shell;
        stateDir = mkDefault cfg.stateDir;
        branding.name = mkDefault cfg.branding.name;
        # The keyboard layout the system was set up with.
        keyboard = {
          layout = mkDefault config.services.xserver.xkb.layout;
          variant = mkDefault (if config.services.xserver.xkb.variant == "" then null else config.services.xserver.xkb.variant);
        };
        cursor = {
          enable = mkDefault cfg.cursor.enable;
          package = mkDefault cfg.cursor.package;
          name = mkDefault cfg.cursor.name;
          size = mkDefault cfg.cursor.size;
        };
      }
      // lib.optionalAttrs (cfg.stateDirPath != null) { stateDirPath = mkDefault cfg.stateDirPath; }
      // lib.optionalAttrs (cfg.configDir != null) { configDir = mkDefault cfg.configDir; }
      // lib.optionalAttrs (cfg.rebuildCommand != null) { rebuildCommand = mkDefault cfg.rebuildCommand; };
    }));
  })
  ]);
}
