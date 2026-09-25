# This machine. flake.nix also imports ./hardware-configuration.nix; generate
# it on the machine: nixos-generate-config --show-hardware-config > hardware-configuration.nix
{ ... }:
let
  # Your login, and where this flake lives. The Omarchy menu edits the
  # state files in ./omarchy and rebuilds from here, so keep it in your home.
  user = "me";
  configDir = "/home/${user}/nixos";
in
{
  omarchy = {
    enable = true;
    users = [ user ];
    # What the menu installs, the active theme and the dev databases.
    stateDir = ./omarchy;
    inherit configDir;
    # Log straight in when the disk is encrypted (the passphrase already
    # proved who's there), as Omarchy does:
    # login.autoLogin = user;

    # The desktop above is Omarchy's essentials. Its whole ecosystem (its
    # app picks, web apps, CLI and development tools, with their keybinds
    # and Docker) is one switch, and each layer can be set on its own in
    # the user's config below (omarchy.apps / webapps / cli / development):
    # ecosystem.enable = true;
  };

  # Your own apps and keybinds on top of Omarchy's, e.g.:
  home-manager.users.${user} = { pkgs, ... }: {
    home.stateVersion = "26.05";
    # home.packages = [ pkgs.spotify ];
    # omarchy.keybinds."SUPER + SHIFT + M".launch = "spotify";
    # Omarchy's web apps, but only some of them:
    # omarchy.webapps = { enable = true; picks = [ "hey" "youtube" ]; };
  };

  users.users.${user} = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "video" ];
    # Set a password with `passwd` after the first boot, or:
    # initialPassword = "changeme";
  };

  networking.hostName = "omarchy";
  time.timeZone = "Europe/Amsterdam";
  i18n.defaultLocale = "en_US.UTF-8";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  nixpkgs.config.allowUnfree = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  system.stateVersion = "26.05";
}
