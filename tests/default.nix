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
#             the shell's unit and the commands in place for the user;
#             screenshots saved (menu command, PRINT, `save`), the recorder
#             found and stopped, the sleep lock and crash watch running
{ inputs, pkgs, self }:
let
  inherit (pkgs.stdenv.hostPlatform) system;

  # Upstream's screenshot command hands off to omasnap on its development
  # branch; the v4.0 releases (the stable channel) run a grim script.
  omasnapScreenshots = pkgs.lib.hasInfix "omasnap" (
    builtins.readFile "${inputs.omarchy}/bin/omarchy-capture-screenshot"
  );

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

  # Run a command the way the shell's menu runs an action: in the
  # omarchy-shell service's cgroup, as the user, with the shell's
  # environment, through `bash -lc` (Quickshell's execDetached).
  menuAction = pkgs.writeShellScript "menu-action" ''
    pid=$(systemctl --user -M omarchy@ show -p MainPID --value omarchy-shell.service)
    cg=$(systemctl --user -M omarchy@ show -p ControlGroup --value omarchy-shell.service)
    echo $$ >"/sys/fs/cgroup$cg/cgroup.procs"
    mapfile -d "" envs <"/proc/$pid/environ"
    cd /home/omarchy
    exec setpriv --reuid=1000 --regid=100 --init-groups env -i "''${envs[@]}" bash -lc "$1"
  '';

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
    nodes.machine = { lib, pkgs, ... }: {
      # For the test script's checks (run as root).
      environment.systemPackages = [ pkgs.jq ];
      # The menu's rebuilds: the user may sudo (as on a real install), and
      # "rebuilding" switches to a prebuilt generation the way nixos-rebuild
      # does (switch-to-configuration in its own transient unit). That
      # generation is what the host's flake would build after the menu
      # edits in this test: helix added to apps.json, catppuccin picked.
      users.users.omarchy.extraGroups = [ "wheel" ];
      security.sudo.wheelNeedsPassword = false;
      omarchy.rebuildCommand =
        "sudo systemd-run --collect --no-ask-password --pipe --quiet --service-type=exec "
        + "--unit=nixos-rebuild-switch-to-configuration --wait "
        + "/run/booted-system/specialisation/rebuilt/bin/switch-to-configuration test"
        # Only reached when the rebuild's terminal survives the switch.
        + " && touch /tmp/rebuild-finished";
      # A non-US keyboard, as the installer sets it: Hyprland takes it.
      services.xserver.xkb.layout = "de";
      specialisation.rebuilt.configuration.omarchy.stateDir = lib.mkForce ./state-rebuilt;
      # The menu's Timezone entry goes through polkit, whose agent (the
      # shell) would ask for the password on screen.
      security.polkit.extraConfig = ''
        polkit.addRule(function(action, subject) {
          if (action.id == "org.freedesktop.timedate1.set-timezone" && subject.user == "omarchy")
            return polkit.Result.YES;
        });
      '';
    };
    nodes.ecosystem = { pkgs, ... }: {
      # A declared time zone: the menu's Timezone entry points to the config.
      time.timeZone = "Europe/Amsterdam";
      omarchy.ecosystem.enable = true;
      # bash instead of zsh; foot, Nautilus and btop left out, Alacritty as
      # the terminal (the installer's choices).
      omarchy.shell = "bash";
      home-manager.users.omarchy = {
        home.packages = [ pkgs.alacritty ];
        omarchy = {
          apps.picks = [ "pinta" "omacalc" ];
          webapps.picks = [ "youtube" ];
          defaultApps.foot.enable = false;
          defaultApps.nautilus.enable = false;
          defaultApps.btop.enable = false;
          terminal = "Alacritty.desktop";
        };
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

      # Capture tools, run in the session's environment as the menu and
      # the keybinds run them. The folders Omarchy saves into exist.
      machine.succeed(f"test -d {home}/Pictures && test -d {home}/Videos && test -d {home}/Downloads")
      session = env + " WAYLAND_DISPLAY=$(cd /run/user/1000 && ls wayland-? | head -1)"
      # Upstream's screenshot command: omasnap on its development branch,
      # a grim script in the v4.0 releases the stable channel follows.
      omasnap = ${if omasnapScreenshots then "True" else "False"}
      shots = f"{home}/Pictures/Screenshots" if omasnap else f"{home}/Pictures"
      # Capture > Screenshot: copies to the clipboard and saves (omasnap:
      # with auto-save); fullscreen needs no selection.
      machine.succeed(f"{user} '{session} timeout 60 omarchy-capture-screenshot fullscreen'")
      machine.wait_until_succeeds(f"ls {shots}/screenshot-*.png", timeout=30)
      machine.succeed(f"{user} '{session} wl-paste --list-types' | grep -qx image/png")
      if omasnap:
          # PRINT, then Ctrl+A (the whole monitor) in Omasnap's picker: the
          # keybind path, saved the same way.
          count = int(machine.succeed(f"ls {shots} | wc -l").strip())
          machine.send_key("print")
          machine.sleep(3)
          machine.send_key("ctrl-a")
          machine.wait_until_succeeds(f"test $(ls {shots} | wc -l) -gt {count}", timeout=30)
      # Quick output saves when asked: `save`.
      count = int(machine.succeed(f"ls {shots} | wc -l").strip())
      machine.succeed(f"{user} '{session} timeout 60 omarchy-capture-screenshot fullscreen save'")
      machine.wait_until_succeeds(f"test $(ls {shots} | wc -l) -gt {count}", timeout=30)
      machine.succeed(f"{user} 'file {shots}/screenshot-*.png' | grep -q 'PNG image data'")

      # Screen recording: Omarchy finds the running recorder by its process
      # name (the bar indicator, Stop, the toggle). gpu-screen-recorder
      # refuses the VM's software OpenGL, so the recorder's own wrapper runs
      # a sleeping Python in its place: started under the name Omarchy
      # looks for, and stopped (SIGINT) by Omarchy's command.
      machine.succeed(
        "mkdir -p /tmp/gsr && py=$(su - omarchy -c 'readlink -f $(command -v python3)') "
        "&& sed -E \"s#^exec -a gpu-screen-recorder \\\"[^\\\"]*\\\"#exec -a gpu-screen-recorder $py#\" "
        "\"$(su - omarchy -c 'readlink -f $(command -v gpu-screen-recorder)')\" </dev/null >/tmp/gsr/gpu-screen-recorder "
        "&& chmod +x /tmp/gsr/gpu-screen-recorder && grep -q '^exec -a gpu-screen-recorder /nix/store/.*python' /tmp/gsr/gpu-screen-recorder"
      )
      machine.succeed("systemd-run --user -M omarchy@ --unit=fake-recorder /tmp/gsr/gpu-screen-recorder -c 'import time; time.sleep(300)'")
      machine.wait_until_succeeds("pgrep -f '^gpu-screen-recorder'", timeout=30)
      machine.succeed(f"{user} '{session} omarchy-capture-screenrecording --stop-recording'")
      machine.wait_until_fails("pgrep -f '^gpu-screen-recorder'", timeout=30)

      # Upstream's user units: lock before suspend, crash capture.
      machine.succeed("systemctl --user -M omarchy@ is-active omarchy-sleep-lock.service omarchy-crash-watch.service")
      machine.succeed("systemd-inhibit --list | grep -q 'Lock screen before suspend'")
      # Commands the capture and share tools call by name.
      machine.succeed(f"{user} 'command -v v4l2-ctl hyprpicker grim slurp tesseract zbarimg wl-copy localsend lspci'")

      # ---- The user's own files --------------------------------------------
      # Upstream's config/hypr files, seeded once as regular files the user
      # owns and edits (the menu opens them); hyprland.lua stays generated.
      hypr = f"{home}/.config/hypr"
      userfiles = ["monitors.lua", "input.lua", "bindings.lua", "looknfeel.lua", "autostart.lua", "hyprsunset.conf"]
      for f in userfiles:
          machine.succeed(f"test -f {hypr}/{f} && test ! -L {hypr}/{f}")
          machine.succeed(f"test $(stat -c %U {hypr}/{f}) = omarchy")
          machine.succeed(f"{user} 'test -w {hypr}/{f}'")
      machine.succeed(f"test -L {hypr}/hyprland.lua")
      upstream = machine.succeed(f"readlink -f {home}/.local/share/omarchy").strip()
      machine.succeed(f"cmp {hypr}/input.lua {upstream}/config/hypr/input.lua")
      # The menu's Setup > Monitors / Input / Keybindings and Style > Hyprland
      # are upstream's own entries again: they open these files.
      # The NixOS menu layer lives in the package's menu; the extension file
      # is the user's (upstream's commented template).
      ext = f"{home}/.config/omarchy/extensions/omarchy-menu.jsonc"
      machine.succeed(f"test -f {ext} && test ! -L {ext} && cmp {ext} {upstream}/config/omarchy/extensions/omarchy-menu.jsonc")
      nixos_menu = machine.succeed(f"sed -n '/NixOS (nix-desktops/,$p' {upstream}/default/omarchy/omarchy-menu.jsonc")
      assert '"setup.config.hyprland"' in nixos_menu and '"install.package"' in nixos_menu, nixos_menu
      for entry in ["setup.monitors", "setup.input", "setup.keybindings", "style.hyprland"]:
          assert f'"{entry}"' not in nixos_menu, f"{entry} is still overridden"

      # Omarchy's program configs and ~/.zshrc are the user's files too.
      configs = [".config/foot/foot.ini", ".config/starship.toml", ".config/tmux/tmux.conf",
                 ".config/btop/btop.conf", ".config/lazygit/config.yml", ".config/fastfetch/config.jsonc",
                 ".config/alacritty/alacritty.toml", ".config/ghostty/config", ".config/kitty/kitty.conf",
                 ".zshrc", ".zshenv"]
      for f in configs:
          machine.succeed(f"test -f {home}/{f} && test ! -L {home}/{f} && test $(stat -c %U {home}/{f}) = omarchy")
      btop_theme = f"cmp {home}/.config/btop/themes/current.theme {home}/.local/state/omarchy/current/theme/btop.theme"
      machine.succeed(btop_theme)
      # Omarchy's font switcher edits them in place (sed -i), and the next
      # activation still succeeds and keeps the edit.
      machine.succeed(f"{user} '{session} DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus omarchy-font-set \"Liberation Mono\"'")
      machine.succeed(f"grep -q '^font=Liberation Mono' {home}/.config/foot/foot.ini")
      machine.succeed(f"{user} 'echo \"alias hi=\\\"echo hi\\\"\" >> ~/.zshrc'")

      # The system's keyboard layout (services.xserver.xkb.layout).
      layout = machine.succeed(f"{user} '{env} hyprctl getoption input:kb_layout'")
      assert "de" in layout, layout
      # (The font switch restarted the shell: retry until its menu answers.)
      for _ in range(12):
          machine.execute(f"{user} '{session} omarchy-menu summon setup.monitors'")
          if machine.execute(f"sleep 5; pgrep -u omarchy -f 'nvim.*{hypr}/monitors.lua'")[0] == 0:
              break
      else:
          raise Exception("Setup > Monitors didn't open monitors.lua")
      machine.succeed("pkill -u omarchy -f 'nvim.*monitors.lua'")

      # Edits survive Home Manager re-activation (every rebuild runs it).
      machine.succeed(f"{user} 'echo \"-- my input tweak\" >> {hypr}/input.lua'")
      # Omarchy's scale command writes the scale into monitors.lua.
      machine.succeed(f"{user} '{session} omarchy-hyprland-monitor-scaling 2'")
      machine.succeed(f"grep -qx 'local omarchy_monitor_scale = 2' {hypr}/monitors.lua")
      scale = f"{user} '{env} hyprctl monitors -j' | jq -e '.[0].scale == 2'"
      machine.succeed(scale)
      # A copy made in ~/.local/state/hypr (loaded first) moves to
      # ~/.config/hypr when that one is untouched; an older link into the
      # store becomes a copy.
      machine.succeed(f"{user} 'mkdir -p ~/.local/state/hypr && cp {hypr}/looknfeel.lua ~/.local/state/hypr/ && chmod u+w ~/.local/state/hypr/looknfeel.lua && echo \"-- my look\" >> ~/.local/state/hypr/looknfeel.lua'")
      machine.succeed(f"{user} 'rm {hypr}/autostart.lua && ln -s {upstream}/config/hypr/autostart.lua {hypr}/autostart.lua'")
      machine.succeed("systemctl restart home-manager-omarchy.service")
      machine.succeed("systemctl is-active home-manager-omarchy.service")
      machine.succeed(f"grep -qx -- '-- my input tweak' {hypr}/input.lua")
      machine.succeed(f"grep -qx -- '-- my look' {hypr}/looknfeel.lua")
      machine.succeed(f"grep -q '^font=Liberation Mono' {home}/.config/foot/foot.ini")
      machine.succeed(f"{user} 'zsh -ic hi' | grep -qx hi")
      machine.succeed(f"test ! -e {home}/.local/state/hypr/looknfeel.lua")
      machine.succeed(f"test -f {hypr}/autostart.lua && test ! -L {hypr}/autostart.lua")
      machine.succeed(f"grep -qx 'local omarchy_monitor_scale = 2' {hypr}/monitors.lua")
      machine.succeed(f"{user} '{env} hyprctl reload'")
      machine.sleep(2)
      machine.succeed(scale)
      errors = machine.succeed(f"{user} '{env} hyprctl configerrors'").strip()
      assert errors in ("", "no errors"), f"Hyprland config errors:\n{errors}"

      # ---- XDG user directories ---------------------------------------------
      for d in ["Documents", "Downloads", "Music", "Pictures", "Projects", "Videos"]:
          machine.succeed(f"test -d {home}/{d}")
      dirs = machine.succeed(f"cat {home}/.config/user-dirs.dirs")
      assert 'XDG_PICTURES_DIR="$HOME/Pictures"' in dirs, dirs
      # As upstream: Desktop, Templates and Public are the home directory.
      assert 'XDG_DESKTOP_DIR="$HOME"' in dirs, dirs
      # The user's file (xdg-user-dirs-update can change it).
      machine.succeed(f"test -f {home}/.config/user-dirs.dirs && test ! -L {home}/.config/user-dirs.dirs")
      pictures = machine.succeed(f"{user} 'xdg-user-dir PICTURES'").strip()
      assert pictures == f"{home}/Pictures", pictures
      machine.succeed(f"grep -qx 'file://{home}/Downloads Downloads' {home}/.config/gtk-3.0/bookmarks")

      # ---- The cursor -------------------------------------------------------
      machine.succeed(f"test -f {home}/.local/share/icons/Bibata-Modern-Classic/cursors/left_ptr")
      machine.succeed("grep -qx 'CursorTheme=Bibata-Modern-Classic' /etc/sddm.conf.d/00-nixos.conf")
      machine.succeed("grep -q '^CompositorCommand=.*XCURSOR_THEME=Bibata-Modern-Classic' /etc/sddm.conf.d/00-nixos.conf")
      foot = machine.succeed("pgrep -u omarchy -x foot | head -1").strip()
      fenv = machine.succeed(f"tr '\\0' '\\n' < /proc/{foot}/environ")
      for var in ["XCURSOR_THEME=Bibata-Modern-Classic", "XCURSOR_SIZE=24",
                  "HYPRCURSOR_THEME=Bibata-Modern-Classic", "HYPRCURSOR_SIZE=24"]:
          assert var in fenv.splitlines(), f"{var} not in the session: {fenv}"
      bus = "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"
      theme = machine.succeed(f"{user} '{bus} dconf read /org/gnome/desktop/interface/cursor-theme'").strip()
      assert theme == "'Bibata-Modern-Classic'", theme
      # The pointer on screen, over the desktop between the window and the
      # edge (the monitor is at scale 2 now: 640x400 logical). The VM draws
      # it in software, so QEMU's screendump shows it.
      machine.succeed(f"{user} '{env} hyprctl eval \"hl.dispatch(hl.dsp.cursor.move({{ x = 5, y = 200 }}))\"'")
      machine.succeed(f"{user} '{env} hyprctl cursorpos' | grep -qx '5, 200'")
      machine.sleep(1)
      machine.screenshot("cursor")
      machine.succeed(f"{user} '{session} grim -c /tmp/cursor-grim.png'")
      machine.copy_from_machine("/tmp/cursor-grim.png", "")

      # ---- Theme switching, live --------------------------------------------
      # The config the menu edits, as on a real install: a writable copy.
      machine.succeed(f"{user} 'mkdir -p ~/nixos && cp -r --no-preserve=mode ${./state} ~/nixos/omarchy'")
      theme_json = f"{home}/nixos/omarchy/theme.json"
      machine.succeed(f"test -f {theme_json}")
      current = f"{home}/.local/state/omarchy/current"
      border = f"{user} '{env} hyprctl getoption general:col.active_border'"
      before = machine.succeed(border)
      gen = machine.succeed("readlink /run/current-system").strip()
      machine.succeed(f"{user} '{session} {bus} omarchy-theme-set catppuccin'")
      machine.succeed(f"jq -e '.theme == \"catppuccin\"' {theme_json}")
      machine.succeed(f"grep -qx catppuccin {current}/theme.name")
      machine.succeed(f"cmp {current}/theme/colors.toml {home}/.config/omarchy/themes/catppuccin/colors.toml")
      icons = machine.succeed(f"{user} '{bus} dconf read /org/gnome/desktop/interface/icon-theme'").strip()
      assert icons == "'Yaru-purple'", icons
      machine.succeed(btop_theme)
      machine.succeed(f"readlink -f {current}/background | grep -q '^{current}/theme/backgrounds/'")
      for _ in range(30):
          if machine.succeed(border) != before:
              break
          machine.sleep(1)
      else:
          raise Exception(f"Hyprland's border kept the old theme's color: {before}")
      assert machine.succeed("readlink /run/current-system").strip() == gen, "the theme switch rebuilt"
      # The switch reloaded Hyprland; the edited monitors file stayed.
      machine.succeed(scale)
      machine.succeed(f"grep -qx 'local omarchy_monitor_scale = 2' {hypr}/monitors.lua")
      # Re-activating the same generation keeps the live pick.
      machine.succeed("systemctl restart home-manager-omarchy.service")
      machine.succeed(f"grep -qx catppuccin {current}/theme.name")
      machine.succeed(f"cmp {current}/theme/colors.toml {home}/.config/omarchy/themes/catppuccin/colors.toml")

      # ---- Install > Package, then the wrapper again ------------------------
      # Install > Package: the menu runs `xdg-terminal-exec … omarchy-pkg-install`
      # from inside the shell's service, and the wrapper edits apps.json and
      # rebuilds (here: switches to the prebuilt generation, which also has a
      # new theme, so the shell restarts mid-rebuild). The search needs
      # nixpkgs online, so the wrapper runs with the pick (helix) as the
      # search would, in the shell's cgroup and environment, as the menu's
      # action does.
      terminals = f"{user} '{env} hyprctl clients -j' | jq '[.[] | select(.class == \"org.omarchy.terminal\")] | length'"
      shell_pid = machine.succeed("systemctl --user -M omarchy@ show -p MainPID --value omarchy-shell.service").strip()
      machine.succeed("${menuAction} 'xdg-terminal-exec --app-id=org.omarchy.terminal omarchy-pkg-install helix' >/dev/null 2>&1 &")
      machine.wait_until_succeeds(f"readlink /run/current-system | grep -qv {gen}", timeout=300)
      # The wrapper's terminal outlived the shell's restart and finished.
      machine.wait_until_succeeds("test -e /tmp/rebuild-finished", timeout=120)
      # The shell came back (restarted for the new theme), not stuck
      # stopping behind the wrapper's sudo.
      machine.wait_until_succeeds(f"test \"$(systemctl --user -M omarchy@ show -p MainPID --value omarchy-shell.service)\" != {shell_pid}", timeout=120)
      machine.wait_until_succeeds(shell, timeout=60)
      machine.wait_until_succeeds(f"{user} 'command -v hx'", timeout=120)
      machine.succeed(f"jq -e '.packages | index(\"helix\")' {home}/nixos/omarchy/apps.json")
      machine.wait_for_unit("home-manager-omarchy.service")
      machine.sleep(5)
      # The rebuild kept the theme (theme.json's now) and the user's files.
      machine.succeed(f"grep -qx catppuccin {current}/theme.name")
      machine.succeed(f"grep -qx 'local omarchy_monitor_scale = 2' {hypr}/monitors.lua")
      machine.succeed(f"grep -qx -- '-- my input tweak' {hypr}/input.lua")
      machine.succeed(f"{user} '{env} hyprctl reload'")
      machine.sleep(2)
      machine.succeed(scale)
      # Install > Package opens its wrapper again after the rebuild.
      machine.succeed(shell)
      count = int(machine.succeed(terminals).strip())
      machine.succeed(f"{user} '{session} omarchy-menu summon install.package'")
      machine.wait_until_succeeds(f"test $({terminals}) -gt {count}", timeout=60)
      machine.succeed("pgrep -u omarchy -f 'omarchy-pkg-install$'")
      machine.screenshot("install-wrapper")

      # ---- Timezone ---------------------------------------------------------
      machine.fail("test -e /etc/omarchy/time-zone")
      machine.succeed(f"{user} '{session} omarchy-menu-timezone Europe/Amsterdam'")
      machine.succeed("timedatectl show -p Timezone --value | grep -qx Europe/Amsterdam")

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
      # bash as the shell: Omarchy's setup in the user's ~/.bashrc, no zsh.
      eco.succeed("getent passwd omarchy | grep -q '/bash$'")
      eco.succeed(f"test -f {home}/.bashrc && test ! -L {home}/.bashrc && test ! -e {home}/.zshrc")
      eco.fail(f"{user} 'command -v zsh'")
      alias = eco.succeed(f"{user} 'bash -ic \"alias ls\"' 2>&1")
      assert "eza" in alias, alias
      # Default apps left out: not installed, their binds and MIME defaults
      # gone; the terminal bind launches the chosen terminal.
      for app in ["foot", "nautilus", "btop"]:
          eco.fail(f"{user} 'command -v {app}'")
      for dropped in ["File manager", "Activity"]:
          assert dropped not in binds.splitlines(), f"bind not dropped: {dropped}"
      eco_term = eco.succeed(f"{user} 'xdg-terminal-exec --print-id'").strip()
      assert eco_term.startswith("Alacritty.desktop"), eco_term
      mime = f"$(readlink -f {home}/.local/share/omarchy)/../applications/mimeapps.list"
      eco.succeed(f"grep -q chromium.desktop {mime}")
      eco.fail(f"grep -q Nautilus {mime}")
      eco.fail(f"test -e {home}/.config/foot/foot.ini")
      # A declared time zone: the menu's Timezone entry says where to change it.
      eco.succeed("grep -qx Europe/Amsterdam /etc/omarchy/time-zone")
      out = eco.fail(f"{user} 'omarchy-menu-timezone Europe/Berlin 2>&1'")
      assert "time.timeZone" in out, out
      eco.succeed("timedatectl show -p Timezone --value | grep -qx Europe/Amsterdam")
    '';
  };
}
