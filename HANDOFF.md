# Handoff: nix-desktops/omarchy

You are picking up **nix-desktops/omarchy** (this repo, `~/Projects/omarchy`,
remote `github.com/nix-desktops/omarchy`, GPL-3.0). Read this whole file before
changing anything.

## The goal

A **standalone NixOS flake that gives a full Omarchy desktop** on any NixOS
machine. [Omarchy](https://omarchy.org) is basecamp's opinionated Arch +
Hyprland setup. Here it is taken **remotely from upstream**
(`github:basecamp/omarchy`, a non-flake input), so Omarchy updates flow in, and
adapted declaratively for NixOS.

- **Keep everything that makes Omarchy Omarchy:** the Quickshell shell (bar,
  dropdown panels, menu, notifications, OSD, lock, idle, polkit, clipboard,
  wallpaper), every keybind, the look and feel, the themes, the commands, and
  Omarchy's CLI configs.
- **What's installed by default, what's Omarchy's ecosystem and what's only
  picked** is decided in [PACKAGES.md](PACKAGES.md): integrated tools, default
  apps, the CLI setup and the TUI launchers are default; Omarchy's app picks,
  web apps and development tools are the ecosystem, behind one switch,
  `omarchy.ecosystem.enable` (**off by default**), with a switch and picks per
  layer; AI agents and their CLIs are only what the user lists. Users choose
  their own apps and bind them with `omarchy.keybinds`.
- **Standalone:** a fresh NixOS install must be able to use this flake alone.
  It must not depend on the author's personal config (`~/nixos`), which is
  currently just one consumer (see "Consumers").
- Later, the configurator (`nix-composer/configurator`, `~/Projects/configurator`)
  will offer this desktop as one choice in its installer and write these
  options into the user's flake. Keep the option surface clean and
  declarative for that.

## Ground rules

- **Commit identity:** author and committer `Simbaclaws <github@hylke.it>`,
  passed per command (`GIT_AUTHOR_NAME=Simbaclaws GIT_AUTHOR_EMAIL=github@hylke.it
  GIT_COMMITTER_NAME=Simbaclaws GIT_COMMITTER_EMAIL=github@hylke.it`; no global
  git identity is set on this machine). **Never add a `Co-Authored-By` trailer
  or any AI attribution** to commits or PR bodies.
- **First push:** nothing of this work is committed yet. The repo has only the
  GitHub-created "Initial commit" (LICENSE). Squash the work into **one commit**
  on top of it, then **ask the user before pushing**.
- **Don't modify `~/nixos`** without asking; it's the user's personal config
  and only consumes this flake. The user's live machine runs this desktop, so
  don't rebuild or switch their system unless they ask.
- Keep as much as possible **remote**: prefer reading, patching or wrapping
  upstream files over copying them into this repo.

## Repo map

```
flake.nix               inputs: nixpkgs (26.05), nixpkgs-unstable, omarchy (upstream, non-flake),
                        omarchy-zsh, Omarchy's tools (omasnap, ttfx, owe, elsewhen, omacut,
                        omacalc, omawrite, aether, herdr, tobi-try, omarchy-pkgs, lazyvim-starter;
                        all non-flake, pinned to the versions Omarchy ships), dev-templates,
                        home-manager (tests only)
                        outputs: homeManagerModules.default, nixosModules.default, lib.theme,
                        lib.catalog, templates (dev environments + host), packages (omarchy,
                        keybinds, the tools), checks
pkgs/omarchy.nix        upstream Omarchy packaged: share/omarchy (= OMARCHY_PATH) + bin links;
                        shebangs patched, `replacements` installed over upstream commands, shell
                        `plugins` (elsewhen) installed, /usr paths pointed at the profiles, the
                        pacman update widget dropped from the bar
pkgs/tools/             Omarchy's own tools, built from their repos (herdr: its own nix/package.nix)
pkgs/keybinds/          upstream's bind modules run under a stub Lua → keybinds.json
lib/catalog.nix         everything installable, as data, grouped as PACKAGES.md (lib.catalog)
modules/home/default.nix  the desktop (Home Manager): options, the shell and owed as systemd user
                        services, runtime deps, theme hierarchy, menu layer, NixOS commands
modules/home/hyprland.nix Omarchy's Hyprland config (generated hyprland.lua), keybinds option;
                        drops the binds of apps that aren't installed
modules/home/apps.nix   default apps (omarchy.defaultApps: foot, Chromium, Nautilus, Neovim with
                        omarchy-nvim seeded, viewers, system tools), fonts, GTK look, keyring
modules/home/catalog.nix  CLI tools + TUI launchers (default, opt-out), ecosystem layers (apps,
                        webapps, development: enable + picks), agents (+ agents.json state,
                        defaultAgent), tools
modules/home/shell.nix  CLI setup: omarchy.shell (zsh: omarchy.zsh = omarchy-zsh's zoptions +
                        upstream default/bash; bash: upstream rc), omarchy.configs.<program>
modules/nixos/default.nix system side: Hyprland 0.56 (unstable) + uwsm, services the shell and core
                        apps need, lock PAM services, SDDM login + Plymouth splash (Omarchy's
                        themes), docker databases, and the desktop for `omarchy.users` via HM
examples/host/          `templates.host`: a whole NixOS machine (nix flake new -t …#host)
bin/*.sh                NixOS versions of Omarchy commands (installed over upstream's)
lib/theme.nix           theme registry: 22 built-in + pinned community themes; colors.toml /
                        alacritty.toml → palette, ANSI, Stylix base16
lib/menu.nix            NixOS layer over Omarchy's menu (see "Gotchas")
lib/dev-templates.nix   nix-templates/dev + local framework layers (templates/)
data/community-themes.json  112 community themes from Omarchy's manual (owner/repo)
tests/                  flake checks: package, example home config, themes, host template, NixOS
                        VM test (auto-login → shell up, no config errors, SUPER+RETURN opens foot)
```

State the menu edits lives **in the host's config**, passed as
`omarchy.stateDir` (a path; read at build time) and `omarchy.stateDirPath` (the
same directory as a writable string for the commands): `apps.json`
(menu-installed packages), `theme.json` (active theme + pinned community themes),
`dbs.json` (dev databases). `omarchy.configDir` is the host flake the menu opens
and updates; `omarchy.rebuildCommand` is how the menu applies changes.

## What works (verified on the author's machine, 2026-09-25)

- The Omarchy shell runs from this flake (Quickshell 0.3.1), Hyprland 0.56.2,
  no `hyprctl configerrors`, Omarchy's full keybind set plus host overrides.
- All 22 built-in themes build through Omarchy's own renderer
  (`omarchy-theme-set-templates`); 112 community themes resolve (install them
  from the menu; they're pinned in `theme.json`).
- The menu layer: Install/Remove through `apps.json`, Arch-only entries hidden,
  NixOS update actions, icons enforced at build time.
- Theme switching, dev-environment scaffolding, databases, font install,
  screenshots, the lock screen's PAM service, Plymouth with the Omarchy theme.
- `nix flake check` passes (2026-09-25), including the two-node VM test:
  SDDM with Omarchy's theme, auto-login into Hyprland, no config errors, the
  shell running, foot/Chromium as defaults, SUPER+RETURN opening foot, zsh
  with Omarchy's aliases/functions, git defaults, omasnap/ttfx/owed, the
  elsewhen widget, omarchy-nvim seeded; and with the ecosystem on and only
  some picks, exactly the picked apps, launchers and binds.
- Standalone: `templates.host` builds a full system with only this flake and
  Home Manager. The NixOS module wires the Home Manager module for every
  user in `omarchy.users` (options `configDir`, `stateDirPath`,
  `rebuildCommand` passed down as defaults).

## Gotchas (each cost real debugging time)

- **`OMARCHY_PATH` must be stable:** `~/.local/share/omarchy`, a link to the
  package. Quickshell identifies the running shell by its config path, so
  `omarchy-shell` IPC must use the same path across rebuilds. Hyprland's Lua
  config loads Omarchy's modules from the **store path** (the link can be
  missing when Hyprland auto-reloads mid-activation), and Omarchy's `envs.lua`
  then exports that store path, so `hyprland.lua` sets `OMARCHY_PATH` back to
  the stable path afterwards. `paths.lua` is preloaded because it falls back to
  `/usr/share/omarchy`.
- **Versions:** upstream targets the newest releases. Hyprland must be **0.56+**
  (0.55 lacks `monitor.reserved`, the `workspace.special_active` event, …) and
  Quickshell **0.3.1+**; both come from nixos-unstable. Hyprland tools
  (hyprshot, hyprpicker, hyprsunset) must come from the same set. Quickshell
  needs `qtimageformats` on `QT_PLUGIN_PATH` for WebP backgrounds.
- **Inside Hyprland's Lua config:** `hl.on` with an unknown event records a
  config error instead of raising (so `pcall` can't probe with it), and running
  `hyprctl` from the config deadlocks Hyprland, which can't answer its socket
  while evaluating the file.
- **The menu extension replaces entries wholesale.** The shell normalizes every
  entry in `~/.config/omarchy/extensions/omarchy-menu.jsonc` (missing fields →
  "", label → id) and overwrites the shipped entry, despite upstream's docs. So
  `lib/menu.nix` parses upstream's `default/omarchy/omarchy-menu.jsonc`, merges
  the overrides onto real entries and writes complete entries, failing the
  build if a visible entry lacks an icon.
- **Nerd Font glyphs:** private-use BMP glyphs (U+E000–U+F8FF) get dropped
  when written literally by some tools, leaving blank icons. Write them as
  escapes: `builtins.fromJSON "\"\\uf313\""` in Nix, `printf '\uf313'` in bash.
- **`writeShellApplication` runs shellcheck;** `runtimeEnv` values containing
  quotes fail it (that's why `omarchy-nixos-rebuild` is generated from
  `rebuildCommand` instead of reading an env var).
- **Upstream on NixOS:** 458 `#!/bin/bash` and 5 `#!/usr/bin/python3` scripts
  (patchShebangs); launchers that check `/usr/bin/<app>` are patched to use
  PATH (pkgs/omarchy.nix); `omarchy-provision-first-run` does Arch first-login
  setup (a no-op here; first-run belongs to a future welcome app); Omarchy's
  autostart launches `udiskie` itself (a runtime dep, so hosts must not also
  run a udiskie service).
- **Stylix** sets its own Plymouth theme; the module uses `mkForce "omarchy"`.
- **Upstream refs:** the Quickshell generation is the default branch
  `quattro` and release tags `v4.*`. Upstream's branches literally named `rc`
  and `dev` are still the **old 3.8 line** (Waybar, no shell); don't track them.
- **Local testing through a consumer:** a `path:` flake input is locked by
  content hash, so after editing this repo run `nix flake update omarchy-desktop`
  in the consumer (`~/nixos`) or it builds the old copy.
- **Two Hyprland copies:** if a host also installs hyprshot or hyprpicker from
  its own nixpkgs, home-manager's buildEnv collides. The host should drop them
  while this desktop is enabled. (The default apps are `lowPrio`, so a host's
  own tealdeer/neovim/… wins over them instead of colliding.)
- **Module dedup:** both modules are wrapped with a `key`, so a host that
  imports the HM module itself *and* lists the user in `omarchy.users` gets
  it once (the author's config does exactly that).
- **Login:** `omarchy.login.enable` defaults off when the host runs greetd,
  GDM or LightDM (the author uses greetd). SDDM's greeter runs in Hyprland
  (`start-hyprland -- --config default/sddm/hyprland.lua`); the theme's
  session match is patched case-insensitive ("Hyprland (UWSM)").
- **Desktop IDs:** nixpkgs names Chromium's entry `chromium-browser.desktop`;
  the wrapped Chromium renames it `chromium.desktop`, the ID Omarchy's
  commands and MIME list use. Upstream looks desktop files up in
  `{~/.local,~/.nix-profile,/usr}` only; the package adds the NixOS profiles.
- **Arch names:** upstream's `omarchy-pkg-add` calls pass Arch/AUR names;
  `bin/omarchy-pkg-attr.sh` maps them to nixpkgs attributes for add, drop and
  present. Extend it when upstream adds installers.
- **Priorities for defaults:** program configs step aside entirely when the
  host enables HM's `programs.<name>` (HM's `xdg.configFile` → `home.file`
  conversion drops priorities, so lazygit/tmux/kitty modules, which write
  `home.file` directly, would conflict), and are otherwise linked at
  `mkOverride 1100` (below `mkDefault`, which HM's own `xdg.configFile.text`
  uses), git defaults go to /etc/gitconfig (the lowest git level), the login
  shell at `mkOverride 900` (NixOS itself sets a `mkDefault` one), GTK dconf
  values at `mkDefault` (Stylix sets them too).
- **QML plugins must match the shell's Qt:** owe-lockfeed builds against
  nixos-unstable's Qt like Quickshell; its QML path is `lib/qt6/qml`.
- **What doesn't build is left out** of the catalog (user's decision): see
  PACKAGES.md. omarchy-default-agent says so for upstream's other agents.
- **Workflows:** PRs made with the default GITHUB_TOKEN don't trigger CI;
  update-omarchy.yml starts ci.yml on the PR branch with workflow_dispatch
  instead (allowed for GITHUB_TOKEN), so no personal token or secret is
  needed for auto-merge.
- **Defaults are system files, not user files:** the terminal list and MIME
  defaults install to the package's `share/` (upstream: `/usr/share`), so
  `omarchy-default-terminal` / `xdg-settings` can still write the user's own
  `~/.config` files. Don't manage those with Home Manager.

## Consumers

`~/nixos` (the author's config; don't change it without asking) imports both
modules through the input `omarchy-desktop` (currently
`path:/home/simbaclaws/Projects/omarchy`; becomes `github:nix-desktops/omarchy`
after the first push). See `~/nixos/modules/omarchy/{home,system,theme}.nix`
for a real consumer: state files, `rebuildCommand`, host keybinds
(`omarchy.keybinds`) and extra Hyprland Lua in `~/nixos/modules/home/hyprland.nix`.

## Status of the planned work (2026-09-25)

All eight items are implemented, squashed into one commit and pushed
(2026-09-25), with the `edge`, `rc` and `stable` branches.

1. **Standalone** — done: `templates.host` (examples/host), the NixOS module
   wires Home Manager for `omarchy.users`, SDDM with Omarchy's theme,
   `login.autoLogin`.
2. **Default apps** — done, per PACKAGES.md groups 1–2 (`apps.nix`).
3. **The ecosystem switch** — done: `omarchy.ecosystem.enable` sets
   `omarchy.{apps,webapps,development}.enable` (NixOS: Docker too); each layer
   has `picks`; `lib.catalog` and `packages.keybinds` export the data for the
   configurator. The CLI setup is default (PACKAGES.md). Developer
   environments are the nix-templates/dev ones (Install > Development);
   developer tooling (group 8) is the `development` layer (user's decision).
4. **AI agents** — done: `omarchy.agents`, `omarchy.defaultAgent` (written to
   `~/.config/omarchy/defaults/agent`, where upstream keeps it now),
   `agents.json` state, a NixOS `omarchy-default-agent` that adds to the state
   and rebuilds. Ids are upstream's names; the 9 that build are listed,
   the rest hidden in the menu.
5. **CLI configs with zsh** — done: `omarchy.shell` (zsh default, bash
   possible), upstream's omarchy-zsh for the zsh-specific part, per-program
   `omarchy.configs.*`.
6. **Omarchy's tools** — packaged (`pkgs/tools`), workarounds retired
   (screenshot replacement, tte patch), elsewhen back in the bar, OWE running
   with the lock-screen feed. aether uses the release binary like Omarchy's
   PKGBUILD. aether and owe are MIT here (as Omarchy's PKGBUILDs say; their
   repos have no license file; the user decided not to ask upstream).
   Upstreaming to nixpkgs: **on hold** (user, 2026-09-25: leave the tool
   packages be for now).
7. **Branches and CI** — workflows written (`ci.yml`, `update-omarchy.yml`).
   Branches `main`, `edge`, `rc`, `stable` exist; auto-merge is allowed and
   the channel branches require the CI check. Cachix (a hosted binary cache)
   stays off until a `CACHIX_AUTH_TOKEN` secret exists (cache name
   `nix-desktops` in ci.yml is a placeholder).
8. **VM test and README** — done.

## Useful commands

```bash
nix build .#checks.x86_64-linux.home     # desktop builds (commands, menu, service)
nix build .#checks.x86_64-linux.themes   # every built-in theme rendered
nix build .#checks.x86_64-linux.vm       # NixOS VM test (two nodes: defaults, ecosystem)
nix build .#checks.x86_64-linux.catalog  # lib/catalog.nix still covers upstream's app binds
nix build .#keybinds                     # upstream's keybinds as JSON
nix flake check                          # all of the above
```

Upstream source for reading: `nix eval --raw .#packages.x86_64-linux.omarchy`
(`share/omarchy` inside it), or `~/.local/share/omarchy` on the author's machine.
