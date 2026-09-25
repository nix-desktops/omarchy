# Flake checks (`nix flake check`, run by CI on every PR and push):
#
#   package   the Omarchy package, shebangs patched, patches applied
#   home      an example Home Manager config with the desktop enabled: the
#             NixOS commands (shellchecked by writeShellApplication), the
#             menu layer (which fails on entries without icons) and the
#             shell service
#   themes    every built-in theme through Omarchy's own renderer
#   tools     every package of Omarchy's own tools (pkgs/tools)
#   catalog   lib/catalog.nix matches upstream: every app and web-app bind
#             upstream defines belongs to an entry, and every entry's bind
#             exists upstream
#   ecosystem-home  the example home with the whole ecosystem and some
#             agents and tools on
#   host      the host template (examples/host) evaluates and its system
#             builds, with a stand-in hardware config
#   vm        a NixOS VM set up like the host template (the NixOS module
#             wiring the desktop for its user): login screen, PAM services,
#             the shell's unit and the commands in place for the user
{ inputs, pkgs, self }:
let
  inherit (pkgs.stdenv.hostPlatform) system;

  exampleHome = {
    home.username = "omarchy";
    home.homeDirectory = "/home/omarchy";
    home.stateVersion = "26.05";
    omarchy = {
      enable = true;
      stateDir = ./state;
      stateDirPath = "/home/omarchy/nixos/omarchy";
      configDir = "/home/omarchy/nixos";
    };
  };

  home = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = [ self.homeManagerModules.default exampleHome ];
  };

  ecosystemHome = inputs.home-manager.lib.homeManagerConfiguration {
    pkgs = import inputs.nixpkgs { inherit system; config.allowUnfree = true; };
    modules = [
      self.homeManagerModules.default
      exampleHome
      {
        omarchy.ecosystem.enable = true;
        # A few of each (from nixpkgs and nixos-unstable): the wiring, not
        # every upstream package, is what's under test.
        omarchy.agents = [ "claude" "codex" "agy" ];
        omarchy.tools = [ "gh" "hunk" ];
      }
    ];
  };

  catalog = self.lib.catalog;
  catalogBinds = pkgs.writeText "catalog-binds.json" (builtins.toJSON
    (pkgs.lib.concatMap (e: e.binds)
      (pkgs.lib.concatMap builtins.attrValues [ catalog.tuis catalog.apps catalog.webapps ])));
in
{
  package = self.packages.${system}.omarchy;

  home = home.activationPackage;

  themes = home.config.omarchy.themes;

  catalog = pkgs.runCommand "omarchy-catalog-check" { nativeBuildInputs = [ pkgs.jq ]; } ''
    upstream=$(jq -c '[.[] | select(.layer != "core") | .keys] | sort' ${self.packages.${system}.keybinds}/keybinds.json)
    ours=$(jq -c 'sort' ${catalogBinds})
    missing=$(jq -rn --argjson u "$upstream" --argjson o "$ours" '$u - $o | .[]')
    stale=$(jq -rn --argjson u "$upstream" --argjson o "$ours" '$o - $u | .[]')
    [ -z "$missing" ] || { echo "Upstream binds not in lib/catalog.nix:"; echo "$missing"; exit 1; }
    [ -z "$stale" ] || { echo "Binds in lib/catalog.nix that upstream no longer has:"; echo "$stale"; exit 1; }
    touch $out
  '';

  ecosystem-home = ecosystemHome.activationPackage;

  tools = pkgs.linkFarm "omarchy-tools" (map (name: { inherit name; path = self.packages.${system}.${name}; })
    (builtins.attrNames (import ../pkgs/tools { inherit pkgs inputs; })));

  host = (inputs.nixpkgs.lib.nixosSystem {
    modules = [
      inputs.home-manager.nixosModules.home-manager
      self.nixosModules.default
      "${../examples/host}/configuration.nix"
      {
        # What nixos-generate-config would write.
        nixpkgs.hostPlatform = system;
        fileSystems."/" = { device = "/dev/disk/by-label/nixos"; fsType = "ext4"; };
        fileSystems."/boot" = { device = "/dev/disk/by-label/boot"; fsType = "vfat"; };
      }
    ];
  }).config.system.build.toplevel;

  vm = pkgs.testers.runNixOSTest {
    name = "omarchy";
    # machine: the essentials, as the host template sets them up.
    # ecosystem: the ecosystem layers on, keeping only some picks.
    defaults = {
      imports = [
        self.nixosModules.default
        inputs.home-manager.nixosModules.home-manager
      ];
      omarchy = {
        enable = true;
        stateDir = ./state;
        users = [ "omarchy" ];
        configDir = "/home/omarchy/nixos";
        # Straight into the session, to check it comes up.
        login.autoLogin = "omarchy";
      };
      users.users.omarchy = {
        isNormalUser = true;
        linger = true;
      };
      home-manager.users.omarchy.home.stateVersion = "26.05";
      virtualisation.memorySize = 4096;
    };
    nodes.machine = { };
    nodes.ecosystem = {
      omarchy.ecosystem.enable = true;
      home-manager.users.omarchy.omarchy = {
        apps.picks = [ "pinta" "omacalc" ];
        webapps.picks = [ "youtube" ];
      };
    };
    testScript = ''
      start_all()
      machine.wait_for_unit("multi-user.target")
      machine.wait_for_unit("home-manager-omarchy.service")

      # Omarchy's login screen.
      machine.wait_for_unit("display-manager.service")
      machine.succeed("test -f /run/current-system/sw/share/sddm/themes/omarchy/Main.qml")

      # Lock-screen PAM service, as the shell requires.
      machine.succeed("test -f /etc/pam.d/omarchy-lock-password")

      # The shell's unit and the NixOS command layer, for the user.
      home = "/home/omarchy"
      machine.succeed(f"test -f {home}/.config/systemd/user/omarchy-shell.service")
      machine.succeed(f"test -e {home}/.local/share/omarchy/shell/shell.qml")
      machine.succeed(f"test -f {home}/.local/state/omarchy/current/theme/shell.toml")
      machine.succeed(f"test -f {home}/.config/omarchy/extensions/omarchy-menu.jsonc")
      machine.succeed("su - omarchy -c 'omarchy-pkg-present bash'")
      machine.fail("su - omarchy -c 'omarchy-pkg-present definitely-not-installed'")
      machine.succeed("su - omarchy -c 'omarchy-theme-set --help >/dev/null 2>&1 || true'")

      # The session: Hyprland from the auto-login, Omarchy's config loading
      # without errors, and the shell running.
      user = "su - omarchy -c"
      shell = "systemctl --user -M omarchy@ is-active omarchy-shell.service"
      machine.wait_until_succeeds(shell, timeout=180)
      # Hyprland answers on its socket (the instance directory appears
      # before it listens; slower machines see the gap).
      env = "XDG_RUNTIME_DIR=/run/user/1000 HYPRLAND_INSTANCE_SIGNATURE=$(ls /run/user/1000/hypr | head -1)"
      hyprland = f"{user} '{env} hyprctl version'"
      machine.wait_until_succeeds(hyprland, timeout=120)
      errors = machine.succeed(f"{user} '{env} hyprctl configerrors'").strip()
      assert errors in ("", "no errors"), f"Hyprland config errors:\n{errors}"
      machine.sleep(10)
      machine.succeed(shell)

      # Core apps: Omarchy's defaults resolve on NixOS.
      term = machine.succeed(f"{user} 'xdg-terminal-exec --print-id'").strip()
      assert term.startswith("foot.desktop"), f"default terminal: {term}"
      browser = machine.succeed(f"{user} 'xdg-mime query default x-scheme-handler/https'").strip()
      assert browser == "chromium.desktop", f"default browser: {browser}"
      machine.succeed(f"{user} 'command -v chromium nautilus nvim imv mpv evince btop lazygit'")

      # The CLI setup: zsh as the login shell with Omarchy's aliases,
      # functions and prompt; git's defaults under the user's own config.
      machine.succeed("getent passwd omarchy | grep -q '/zsh$'")
      zsh = machine.succeed(f"{user} 'zsh -ic \"alias ls; whence -w zd tdl compress; echo \\$EDITOR\"' 2>&1")
      assert "eza" in zsh and "zd: function" in zsh and "tdl: function" in zsh, zsh
      assert "omarchy-launch-editor" in zsh, zsh
      machine.succeed(f"{user} 'git config --get pull.rebase' | grep -qx true")
      machine.succeed(f"{user} 'command -v bat eza rg lazygit starship'")

      # Omarchy's own tools in place of the old workarounds: omasnap for
      # screenshots, ttfx for the screensaver, the elsewhen bar widget, and
      # Omarchy's Neovim config seeded with the theme linked.
      machine.succeed(f"{user} 'command -v omasnap ttfx owed'")
      machine.succeed(f"test -f {home}/.local/share/omarchy/shell/plugins/omacom.elsewhen/manifest.json")
      machine.succeed(f"test -f {home}/.config/nvim/lazyvim.json")
      machine.succeed(f"test -L {home}/.config/nvim/lua/plugins/theme.lua")

      # SUPER+RETURN opens the terminal.
      machine.send_key("meta_l-ret")
      machine.wait_until_succeeds(f"{user} '{env} hyprctl clients' | grep -q 'class: foot'", timeout=60)
      machine.sleep(2)
      machine.screenshot("session")

      # The ecosystem node: kept picks installed and bound, the rest not.
      eco = ecosystem
      eco.wait_for_unit("home-manager-omarchy.service")
      eco.wait_for_unit("docker.service")
      eco.succeed("id -nG omarchy | grep -qw docker")
      eco.succeed(f"{user} 'command -v lazydocker pinta omacalc bat mise'")
      eco.fail(f"{user} 'command -v obsidian'")
      eco.succeed(f"{user} 'ls ~/.nix-profile/share/applications /etc/profiles/per-user/omarchy/share/applications 2>/dev/null | grep -q YouTube.desktop'")
      eco.fail(f"{user} 'ls ~/.nix-profile/share/applications /etc/profiles/per-user/omarchy/share/applications 2>/dev/null | grep -q HEY.desktop'")
      eco.wait_until_succeeds(shell, timeout=180)
      eco.wait_until_succeeds(hyprland, timeout=120)
      binds = eco.succeed(f"{user} '{env} hyprctl binds -j | jq -r \".[].description\"'")
      for kept in ["YouTube", "Docker", "Terminal"]:
          assert kept in binds.splitlines(), f"missing bind: {kept}"
      for dropped in ["X", "Email", "Obsidian", "Omawrite", "Herdr"]:
          assert dropped not in binds.splitlines(), f"bind not dropped: {dropped}"
      errors = eco.succeed(f"{user} '{env} hyprctl configerrors'").strip()
      assert errors in ("", "no errors"), f"Hyprland config errors:\n{errors}"
    '';
  };
}
