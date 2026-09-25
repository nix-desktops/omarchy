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
            stateDir = ./omarchy;              # apps.json, theme.json, dbs.json, agents.json
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
| Omarchy's integrated tools and services (screenshots, screen recording, OCR, the panels' services, printing, input methods, fonts, the login screen, the boot splash) | always | `omarchy.printing.enable`, `omarchy.inputMethod.enable`, `omarchy.login.*`, `omarchy.plymouth.enable` |
| Default apps: foot, Chromium, Nautilus, Neovim (with Omarchy's LazyVim config), imv, mpv, Evince, btop | by default | `omarchy.defaultApps` |
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
| `omarchy.hyprland.extraConfig` | Hyprland Lua after Omarchy's config (monitors, input, window rules) |
| `omarchy.theme` / `omarchy.lib.theme { stateDir = ./omarchy; }` | the active theme's palette, for theming the rest of your config (Stylix, …) |
| `omarchy.login.autoLogin = "me";` | straight into the session, for encrypted disks |

The state the menu edits lives in your config (`stateDir`): `apps.json`
(installed packages), `theme.json` (the theme and pinned community themes),
`dbs.json` (development databases), `agents.json` (installed agents and the
default). Commit it with the rest of your config.

## Channels

The branch you follow is the Omarchy release channel, like Omarchy's own:

| Branch | Follows upstream |
| --- | --- |
| `stable` | the newest `v4.*` release |
| `rc` | the newest `v4.*` pre-release (or stable, when that's newer) |
| `edge` | `quattro`, Omarchy's development branch |
| `main` | this flake's development; changes flow `main` → `edge` → `rc` → `stable` |

`.github/workflows/update-omarchy.yml` checks upstream every 6 hours, re-locks
each channel's `omarchy` input, and merges the update once CI (the full flake
check, including a NixOS VM test that boots the desktop) passes.

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
