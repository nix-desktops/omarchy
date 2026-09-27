# Omarchy on NixOS

[Omarchy](https://omarchy.org), basecamp's Hyprland desktop, as a NixOS flake:
its Quickshell shell (bar, panels, menu, notifications, OSD, lock screen,
idle, polkit agent, clipboard, wallpaper), every keybind, the themes, the
commands and the CLI setup, taken **from upstream** (`basecamp/omarchy`) and
adapted declaratively. Omarchy updates flow in through the flake input;
what's Arch-specific (pacman installs, `/etc` edits, self-update) has a NixOS
version that edits your config and rebuilds.

## Quick start: a new machine

On a NixOS install (the minimal ISO is enough):

```sh
nix flake new -t github:nix-desktops/omarchy#host ~/nixos
cd ~/nixos
$EDITOR configuration.nix          # your user name, time zone
nixos-generate-config --show-hardware-config > hardware-configuration.nix
git init && git add -A             # flakes only see tracked files
sudo nixos-rebuild switch --flake .#omarchy
```

Reboot into Omarchy's login screen. From then on the Omarchy menu
(SUPER+SPACE) installs apps, switches themes, picks defaults and updates the
system by editing `~/nixos/omarchy/*.json` and rebuilding.

## Adding it to an existing config

```nix
{
  inputs.omarchy.url = "github:nix-desktops/omarchy/stable";
  inputs.omarchy.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { nixpkgs, home-manager, omarchy, ... }: {
    nixosConfigurations.my-machine = nixpkgs.lib.nixosSystem {
      modules = [
        home-manager.nixosModules.home-manager
        omarchy.nixosModules.default
        {
          omarchy = {
            enable = true;
            users = [ "me" ];
            stateDir = ./omarchy;              # apps.json, theme.json, dbs.json, agents.json, branding.json
            configDir = "/home/me/nixos";      # this flake, writable by the user
          };
          home-manager.users.me.home.stateVersion = "26.05";
        }
      ];
    };
  };
}
```

With Home Manager's NixOS module imported, the NixOS module gives every user
in `omarchy.users` the desktop. Without it, import
`omarchy.homeManagerModules.default` in each user's Home Manager config and
set the same options there.

## What gets installed

[PACKAGES.md](PACKAGES.md) is the full decision. In short:

| Group | Installed | Options |
| --- | --- | --- |
| Omarchy's integrated tools and services (screenshots, screen recording, OCR, the panels' services, printing, input methods, fonts, the login screen, the boot splash) | always | `omarchy.screenshots.autoSave`, `omarchy.printing.enable`, `omarchy.inputMethod.enable`, `omarchy.login.*`, `omarchy.plymouth.enable` |
| Default apps: foot, Chromium, Nautilus, Neovim (with Omarchy's LazyVim config), imv, mpv, Evince, btop, fastfetch | by default, each opt-out (its binds, MIME defaults and config go with it) | `omarchy.defaultApps.<id>.enable`, `omarchy.terminal`, `omarchy.browser` |
| CLI setup: zsh (or bash) with Omarchy's aliases, functions and prompt; bat, eza, fd, fzf, ripgrep, zoxide, starship, tmux, lazygit, …; Omarchy's configs for them | by default | `omarchy.shell`, `omarchy.cli.<tool>.enable`, `omarchy.configs.<program>.enable` |
| TUI launchers: Docker (lazydocker), Disk Usage, tmux | by default | `omarchy.tuis.<id>.enable` |
| **Omarchy's ecosystem**: its app picks (LibreOffice, Obsidian, OBS, Kdenlive, Pinta, Omarchy's own omacut/omacalc/omawrite/aether, …), its web apps (HEY, YouTube, WhatsApp, …), its development tools and Docker, with their keybinds | with `omarchy.ecosystem.enable` | per layer: `omarchy.{apps,webapps,development}.{enable,picks}` |
| AI coding agents and their CLIs | only what you list | `omarchy.agents`, `omarchy.defaultAgent`, `omarchy.tools` |

The agent integration (the shell's agents panel, SUPER+SHIFT+CTRL+A, the
scratchpad console) is always there; Setup > Defaults > Agent installs the
one you pick.

Every catalog entry, with the ids the options take, is exported as data for
installers such as [nix-composer/configurator](https://github.com/nix-composer/configurator):

```sh
nix eval --json github:nix-desktops/omarchy#lib.catalog     # apps, web apps, CLI, agents, …
nix build github:nix-desktops/omarchy#keybinds               # Omarchy's keybinds as JSON
```

## Options you'll want

| Option | |
| --- | --- |
| `omarchy.keybinds."SUPER + SHIFT + M".launch = "spotify";` | add or replace a bind (`launch`, `webapp`, `tui`, `exec`, `omarchy`, `lua`); `enable = false` removes one |
| `omarchy.hyprland.extraConfig` | Hyprland Lua after Omarchy's config and your keybinds, before your own `~/.config/hypr` files (window rules, devices, …) |
| `omarchy.theme` / `omarchy.lib.theme { stateDir = ./omarchy; }` | the active theme's palette, for theming the rest of your config (Stylix, …) |
| `omarchy.login.autoLogin = "me";` | straight into the session, for encrypted disks |
| `omarchy.terminal = "Alacritty.desktop";` / `omarchy.browser = "brave-browser.desktop";` | the terminal SUPER+RETURN and the menu open, the default browser (defaults: foot and Chromium while installed) |
| `omarchy.keyboard.layout = "de";` | Hyprland's keyboard layout before your `input.lua`; the NixOS module passes `services.xserver.xkb.layout`/`variant` |
| `omarchy.cursor = { package = pkgs.bibata-cursors; name = "Bibata-Modern-Classic"; size = 24; };` | the pointer (these are the defaults): login screen, GTK, XWayland and Hyprland; a host's own `home.pointerCursor` (Stylix, …) wins; `enable = false` leaves it to you |
| `omarchy.branding.name = "Willexander";` | another name on the boot splash, login screen, screensaver and About screen, drawn in Omarchy's style (also Style > Branding in the menu) |

## Your files

As on Arch, the files you and Omarchy's own tools edit are yours, not the
config's: regular files, copied from Omarchy's defaults on the first
activation, kept up to date with the defaults only while you haven't changed
them, and never overwritten once you have (delete one to get the default back
on the next rebuild). A file your own Home Manager config manages
(`xdg.configFile`, `programs.<name>`) is left to it. The Hyprland ones, which
the menu opens:

| File | Menu | |
| --- | --- | --- |
| `~/.config/hypr/monitors.lua` | Setup > Monitors | resolution, position, scale (Omarchy's scale command writes it) |
| `~/.config/hypr/input.lua` | Setup > Input | keyboard layout, repeat, touchpad |
| `~/.config/hypr/bindings.lua` | Setup > Keybindings | your own binds (`o.bind`, `o.rebind`, `hl.unbind`) |
| `~/.config/hypr/looknfeel.lua` | Style > Hyprland | gaps, borders, animations, layout |
| `~/.config/hypr/autostart.lua` | | extra programs at login |
| `~/.config/hypr/hyprsunset.conf` | Setup > Config > Hyprsunset | the night light's schedule |

`~/.config/hypr/hyprland.lua` itself is generated from your NixOS config
(Setup > Config > Hyprland opens that). It loads, in order: Omarchy's
defaults, `omarchy.keybinds`, `omarchy.hyprland.extraConfig`, then the files
above, then Omarchy's toggles, so your files have the last word. Each file is
looked up in `~/.local/state/hypr/` before `~/.config/hypr/` (upstream's
search path): a copy you keep in `~/.local/state/hypr/` is moved to
`~/.config/hypr/` on the next rebuild when the one there is still Omarchy's
default; if you edited both, the state copy keeps winning and the rebuild
warns. A file your Home Manager config manages itself (`xdg.configFile`) is
left to it.

The same goes for Omarchy's program configs (`foot.ini`, `alacritty.toml`,
`kitty.conf`, `ghostty/config`, `btop.conf`, `starship.toml`, `tmux.conf`,
`lazygit/config.yml`, `fastfetch/config.jsonc`; Style > Font and btop's own
settings write to them; they follow the theme through their includes), your
shell's rc (`~/.zshrc` and `~/.zshenv`, or `~/.bashrc` and `~/.bash_profile`
with `omarchy.shell = "bash"`; they source Omarchy's managed setup first, your
lines go below), `~/.config/omarchy/extensions/omarchy-menu.jsonc` (your own
menu entries; the NixOS layer is in the package's menu), and
`~/.config/user-dirs.dirs`.

The XDG user directories are set up as Omarchy does:
Documents, Downloads, Music, Pictures, Projects and Videos, with Desktop,
Templates and Public pointing at your home directory, and the usual ones
bookmarked in the file picker. GTK's dark/light, icon theme and cursor are
system dconf defaults (from `theme.json` and `omarchy.cursor`), so what you
pick in a settings app stays. Screenshots go to `~/Pictures/Screenshots`,
screen recordings to `~/Videos`.

Themes switch live (Style > Theme), as upstream: the shell, Hyprland,
terminals and apps are retinted at once and the pick is written to
`theme.json`, so rebuilds keep it. Only what's built from the theme waits for
the next rebuild: the browser color policy and `omarchy.theme` for your own
theming (Stylix, …). Installing a community theme needs a rebuild (it's
fetched and pinned).

The time zone (Update > Timezone, or middle-click the clock) is set with
`timedatectl` while `time.timeZone` is null in your config; when the config
sets it, the menu says so and you change it there.

The state the menu edits lives in your config (`stateDir`): `apps.json`
(installed packages), `theme.json` (the theme and pinned community themes),
`dbs.json` (development databases), `agents.json` (installed agents and the
default), `branding.json` (the name, when it isn't Omarchy). Commit it with
the rest of your config.

## Shell plugins

Omarchy's shell plugins work as [upstream's manual](https://github.com/basecamp/omarchy/blob/quattro/manual/32-shell-plugins.md)
describes: `omarchy plugin add <git-url> --enable`, `update`, `remove`,
`enable`, `disable`, `clone`, `list`, and Setup > Plugins in the menu. They
live in `~/.config/omarchy/plugins`, which is yours.

Most community plugins ([omarchyplugins.com](https://omarchyplugins.com))
are written for Arch. The NixOS module meets them halfway, both options on
by default:

| Option (NixOS) | |
| --- | --- |
| `omarchy.envfs.enable` | NixOS's envfs on `/usr/bin` and `/bin`: `/usr/bin/python3`, `#!/usr/bin/bash`, `/usr/bin/omarchy-*` resolve to the command on the calling process's PATH (for plugins: the shell's, which has your profile). A command that isn't on that PATH stays missing. |
| `omarchy.usrShare.enable` | `/usr/share/omarchy` (Omarchy's files, where Arch has them) and `/usr/share/zoneinfo` |

and the shell can import `Qt5Compat.GraphicalEffects` and `QtMultimedia`
(`omarchy.qmlModules` in Home Manager).

`omarchy plugin doctor [id|path]` reads a plugin's files (it runs nothing)
and says what it needs here: the commands it runs that aren't on the shell's
PATH and the nixpkgs package for each (from nixpkgs' command-not-found
database, offline), Python modules, QML modules the shell lacks, and what
won't work at all (pacman/AUR, native builds):

```
$ omarchy plugin doctor io.github.sanjuanjor.typist
Typist (io.github.sanjuanjor.typist)   /home/me/.config/omarchy/plugins/io.github.sanjuanjor.typist
  needs packages
  Commands:
    setxkbmap                missing → nixpkgs: setxkbmap   typist_worker.py:45
  Add to your NixOS configuration (then rebuild):
    omarchy.plugins."io.github.sanjuanjor.typist".packages = with pkgs; [ setxkbmap ];
```

`omarchy.plugins` (NixOS or Home Manager) declares plugins, pinned, or only
the packages one added by hand needs:

```nix
omarchy.plugins = {
  "io.github.rookepoole.moon-arc" = {
    url = "https://github.com/rookepoole/omarchy-moon-arc";
    rev = "5efc8d104debdeb922dbc2760aecbc75c565f311";
    hash = "sha256-zYPStMRggvih82neDJ1sTeJ2l1nHUzTu7dMUUM8zmBg=";
    section = "right";          # where on the bar, the first time
  };
  # src = a flake input (flake = false), fetchFromGitHub, a path, …
  # Added with `omarchy plugin add`: just what it runs.
  "io.github.sanjuanjor.typist".packages = [ pkgs.setxkbmap ];
};
```

A declared plugin is checked with upstream's validator at build time and
linked into `~/.config/omarchy/plugins/<id>` (`omarchy plugin update`
leaves it alone). It's switched on the way upstream records it in
`~/.config/omarchy/shell.json`, once: switch it off or move it from the
shell and that sticks; drop it from the config and it's switched off.
`lib.mkPlugin { pkgs; id; src; }` builds one for other uses, and
`lib.catalog.plugins` lists a few that work here.

What doesn't work, and can't from here: plugins that install or query
packages with pacman/yay/paru, ones that need a native build (C++/Rust
helpers, compiled QML plugins) or `npm install`, commands nixpkgs doesn't
have, and fixed paths other than the above (`/usr/lib/…`, `/usr/share/icons/…`,
`/opt/…`). A process that clears its environment and runs a bare
`/usr/bin/<cmd>` still finds it (envfs falls back to the process's original
PATH); one started without the command on its PATH at all does not.
`scripts/plugin-survey` tests the whole directory; see its README.

## Channels

The branch you follow is the Omarchy release channel, like Omarchy's own:

| Branch | Follows upstream |
| --- | --- |
| `stable` | the newest `v4.*` release |
| `rc` | the newest `v4.*` pre-release (or stable, when that's newer) |
| `edge` | `quattro`, Omarchy's development branch |
| `main` | this flake's development; changes flow `main` → `edge` → `rc` → `stable` |

`.github/workflows/update-omarchy.yml` checks upstream every 6 hours, re-locks
each channel's `omarchy` input, runs the full flake check (including a NixOS
VM test that boots the desktop) and pushes the update to the channel only
when it passes.

## How it follows upstream

- `pkgs/omarchy.nix` packages upstream as it is: shebangs patched, the NixOS
  command layer (`bin/`) installed over Arch-only commands, `/usr` paths
  pointed at the profiles.
- Upstream's Hyprland Lua modules, keybinds, menu (`lib/menu.nix` layers the
  NixOS entries over it), themes (rendered by upstream's own renderer), shell
  config (`default/bash`, and `omacom/omarchy-zsh` for zsh) and program
  configs are used from the input directly.
- Omarchy's own tools (omasnap, ttfx, owe, elsewhen, aether, omacut, omacalc,
  omawrite, herdr, try, omarchy-nvim) are built from their upstream repos in
  `pkgs/tools`, at the versions Omarchy ships.
- `checks.catalog` fails when upstream adds an app or web-app keybind the
  catalog doesn't know, so new upstream picks surface in CI.

## Development

```sh
nix flake check                           # everything, the VM test included
nix build .#checks.x86_64-linux.vm        # boots SDDM → Hyprland → the shell
nix build .#checks.x86_64-linux.home      # the desktop's Home Manager config
```

## License

GPL-3.0. Omarchy and its tools are MIT (herdr: Apache-2.0).
