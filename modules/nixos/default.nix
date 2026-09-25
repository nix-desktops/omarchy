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
    environment.systemPackages = lib.optional cfg.login.enable sddmTheme;

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
    # servers, mise), which expect a regular Linux loader.
    programs.nix-ld.enable = mkDefault true;

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
        settings.Wayland.CompositorCommand =
          "${config.programs.hyprland.package}/bin/start-hyprland -- --config ${greeterConfig}";
      };
    };

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
        shell = mkDefault cfg.shell;
        stateDir = mkDefault cfg.stateDir;
        branding.name = mkDefault cfg.branding.name;
      }
      // lib.optionalAttrs (cfg.stateDirPath != null) { stateDirPath = mkDefault cfg.stateDirPath; }
      // lib.optionalAttrs (cfg.configDir != null) { configDir = mkDefault cfg.configDir; }
      // lib.optionalAttrs (cfg.rebuildCommand != null) { rebuildCommand = mkDefault cfg.rebuildCommand; };
    }));
  })
  ]);
}
