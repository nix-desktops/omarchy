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
pkgs/tools/             Omarchy's own tools, built from their repos (herdr: its own nix/package.nix;
                        omasnap with omasnap-autosave.patch)
pkgs/keybinds/          upstream's bind modules run under a stub Lua → keybinds.json
lib/catalog.nix         everything installable, as data, grouped as PACKAGES.md (lib.catalog)
modules/home/default.nix  the desktop (Home Manager): options, the shell, owed and upstream's
                        sleep-lock and crash-watch units as systemd user services, runtime deps,
                        the folders Omarchy saves into, theme hierarchy, menu layer, NixOS commands
modules/home/hyprland.nix Omarchy's Hyprland config (generated hyprland.lua), keybinds option;
                        drops the binds of apps that aren't installed
modules/home/apps.nix   default apps (omarchy.defaultApps.<id>.enable: foot, Chromium, Nautilus, Neovim
                        with omarchy-nvim seeded, viewers, btop, fastfetch; omarchy.terminal/browser),
                        fonts, keyring
modules/home/seed.nix   omarchy.seededFiles: the user's files (hypr/*.lua, program configs, ~/.zshrc,
                        the menu extension, user-dirs.dirs), seeded once, never re-managed
modules/home/catalog.nix  CLI tools + TUI launchers (default, opt-out), ecosystem layers (apps,
                        webapps, development: enable + picks), agents (+ agents.json state,
                        defaultAgent), tools
modules/home/shell.nix  CLI setup: omarchy.shell (zsh: omarchy.zsh = omarchy-zsh's zoptions +
                        upstream default/bash, sourced from a seeded ~/.zshrc; bash: upstream's
                        ~/.bashrc), omarchy.configs.<program> (seeded configs)
modules/nixos/default.nix system side: Hyprland 0.56 (unstable) + uwsm, services the shell and core
                        apps need, lock PAM services, SDDM login + Plymouth splash (Omarchy's
                        themes), docker databases, and the desktop for `omarchy.users` via HM
examples/host/          `templates.host`: a whole NixOS machine (nix flake new -t …#host)
bin/*.sh                NixOS versions of Omarchy commands (installed over upstream's)
modules/home/plugins.nix  shell plugins: omarchy.plugins (declared, pinned; packages), omarchy.qmlModules,
                        declared plugins linked into ~/.config/omarchy/plugins and switched on once
modules/plugin-options.nix  the omarchy.plugins.<id> type (NixOS and Home Manager)
pkgs/plugin.nix         lib.mkPlugin: a plugin's files (+ patches, Nix-built helpers copied into its
                        tree), checked with upstream's validator
pkgs/plugins/           the registry of packaged community plugins, one <manifest id>/default.nix each
                        (found by readDir; README.md there has the conventions); lib.plugins,
                        legacyPackages.<system>.plugins.<id>, omarchy.plugins.<id>.enable
pkgs/plugins-shell-json.py  declared plugins into shell.json (package defaults; once in the user's)
pkgs/plugin-doctor.nix, bin/omarchy-plugin-doctor.py  `omarchy plugin doctor` (packages.plugin-doctor)
pkgs/programs-db.nix    nixpkgs' programs.sqlite (command → package), from the 26.05 channel
scripts/plugin-survey/  the community-plugin survey (survey.py, vm.nix, runtime.py, README.md)
lib/theme.nix           theme registry: 22 built-in + pinned community themes; colors.toml /
                        alacritty.toml → palette, ANSI, Stylix base16
lib/menu.nix            NixOS layer over Omarchy's menu (see "Gotchas")
lib/dev-templates.nix   nix-templates/dev + local framework layers (templates/)
data/community-themes.json  112 community themes from Omarchy's manual (owner/repo)
tests/                  flake checks: package, example home config, themes, host template, NixOS
                        VM test (auto-login → shell up, no config errors, SUPER+RETURN opens foot,
                        screenshots saved, recorder found and stopped, sleep lock armed; the
                        user's files seeded, edited and kept across re-activation and a rebuild;
                        monitor scale kept; XDG dirs; cursor; keyboard layout; live theme switch;
                        Install > Package rebuild from the shell's cgroup; time zone; a bash user
                        with default apps left out on the ecosystem node)
```

State the menu edits lives **in the host's config**, passed as
`omarchy.stateDir` (a path; read at build time) and `omarchy.stateDirPath` (the
same directory as a writable string for the commands): `apps.json`
(menu-installed packages), `theme.json` (active theme + pinned community themes),
`dbs.json` (dev databases), `agents.json` (agents + default) and the optional
`branding.json` (`omarchy.branding.name`, set from Style > Branding: a
wordmark in Omarchy's style on Plymouth, SDDM, screensaver and About;
pkgs/branding.nix). `omarchy.configDir` is the host flake the menu opens
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
- **SDDM's user:** Omarchy's SDDM theme has no user field; it logs in as
  SDDM's last user, which Omarchy's ISO seeds. On a fresh NixOS install
  that's empty (every password "fails" as user ""), so the theme falls back
  to the first of `omarchy.users`. The VM test logs in automatically and
  doesn't cover this.
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
  `home.file` directly, would conflict), and are otherwise seeded as the
  user's files (seed.nix, which also skips any path the host's HM config
  manages), git defaults go to /etc/gitconfig (the lowest git level), the
  login shell at `mkOverride 900` (NixOS itself sets a `mkDefault` one),
  GTK's interface keys in the system dconf database (user values win).
- **QML plugins must match the shell's Qt:** owe-lockfeed builds against
  nixos-unstable's Qt like Quickshell; its QML path is `lib/qt6/qml`.
- **What doesn't build is left out** of the catalog (user's decision): see
  PACKAGES.md. omarchy-default-agent says so for upstream's other agents.
- **Workflows:** PRs and pushes made with GITHUB_TOKEN don't trigger CI, and
  a CI run started by workflow_dispatch doesn't count toward a PR's required
  checks (tried: the PR stays BLOCKED). So update-omarchy.yml runs the flake
  check in its own job and pushes to the channel branch when it passes; the
  channel branches have no branch protection (it would block that push).
  No personal token or secret is needed.
- **Defaults are system files, not user files:** the terminal list and MIME
  defaults install to the package's `share/` (upstream: `/usr/share`), so
  `omarchy-default-terminal` / `xdg-settings` can still write the user's own
  `~/.config` files. Don't manage those with Home Manager.

- **Screenshots aren't saved by upstream's default flow.** Omasnap 1.21
  (Omarchy's screenshot tool since it replaced hyprshot + satty) copies a
  fresh capture and shows a 10-second preview; it writes a file only from
  the editor (Ctrl+S, or Enter = copy + save) or with
  `omarchy-capture-screenshot <mode> save`. That's the same on Arch; older
  Omarchy saved every shot. `omarchy.screenshots.autoSave` (default on,
  user's request) keeps every capture in `~/Pictures/Screenshots` as well
  (pkgs/tools/omasnap-autosave.patch: `OMASNAP_AUTOSAVE` or `[output]
  autosave`; the package sets the env default through its wrapper).
- **Process names under nixpkgs wrappers:** `pgrep -f '^name'` matches the
  command line, and makeWrapper's shell wrappers `exec` the store path of
  `.wrapped/name`. Omarchy finds gpu-screen-recorder that way (the bar's
  recording indicator, Capture > Stop, the ALT+PRINT toggle), so the
  module's gpu-screen-recorder re-execs under the bare name (`exec -a`).
  `pgrep -x` matches the process name: fine for unwrapped binaries and
  Hyprland (which names itself), not for `.foo-wrapped` ones. Check new
  upstream `pgrep`/`pkill` patterns against the real process.
- **Folders:** omarchy-provision-user creates ~/Downloads, ~/Pictures and
  ~/Videos on Arch (and points Desktop, Templates and Public at $HOME); the
  recorder refuses to start without its Videos folder. The module seeds
  user-dirs.dirs the same way and creates every directory it names on
  activation.
- **Upstream's user units** (`default/systemd/user`) aren't installed on
  NixOS by the package; each one needed is declared in modules/home. Done:
  owed, omarchy-sleep-lock (the lock screen before suspend; without it the
  machine resumed unlocked), omarchy-crash-watch. Not done: bt-agent
  (needs bluez-tools), omarchy-recover-internal-monitor, omarchy-fcitx5 (the
  NixOS input-method module runs fcitx5), omarchy-speaker-tuning (specific
  laptops), omarchy-tailscale-receive, omarchy-migrate-notify (Arch
  migrations).
- **The VM can't record the screen:** gpu-screen-recorder refuses Mesa's
  software OpenGL, so the VM test runs Python through the recorder's own
  wrapper to check Omarchy finds and stops it. On the author's machine
  (2026-09-26) the stock wrapper's recording was invisible to
  `pgrep -f '^gpu-screen-recorder'` and the module's was found, stopped with
  SIGINT and left a playable MP4.

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
   Branches `main`, `edge`, `rc`, `stable` exist; the update job tests each
   update itself before pushing it to the channel. Cachix (a hosted binary cache)
   stays off until a `CACHIX_AUTH_TOKEN` secret exists (cache name
   `nix-desktops` in ci.yml is a placeholder).
8. **VM test and README** — done.

## Capture and file-writing tools (audited 2026-09-26)

Against upstream's commands, with the port's PATH (the user profile, the
system, /run/wrappers):

| Tool | Status |
| --- | --- |
| Screenshot (menu, PRINT, omasnap) | worked (copy + preview); now also saved, see Gotchas |
| Screen recording (menu, ALT+PRINT) | fixed: ~/Videos created; recorder found and stopped (`exec -a`) |
| Recording with webcam, webcam list/resize | fixed: v4l-utils (v4l2-ctl) was missing, so the webcam entry never showed |
| Text (OCR), QR, color picker (hyprpicker) | worked: grim, slurp, tesseract (all languages), zbar, wl-clipboard present |
| Share (LocalSend) | fixed: `localsend` (Arch's name) links nixpkgs' `localsend_app` |
| Transcode, yt-dlp host, clipboard open/paste | worked (ImageMagick, ffmpeg; yt-dlp comes with its ecosystem pick) |
| Lock before suspend, Crash Capture | fixed: upstream's user units added |
| hw checks (lspci), terminal restarts (killall) | fixed: pciutils, psmisc |

## The user's files, live themes, shells (2026-09-26)

From a user's reports after installing through the configurator, fixed the
way upstream behaves and covered by the VM test:

- **User files are regular files, not HM links** (`modules/home/seed.nix`,
  `omarchy.seededFiles`): upstream's config/hypr `monitors.lua`,
  `input.lua`, `bindings.lua`, `looknfeel.lua`, `autostart.lua`,
  `hyprsunset.conf`; the program configs (foot, alacritty, kitty, ghostty,
  btop, starship, tmux, lazygit, fastfetch); `~/.zshrc` + `~/.zshenv` (or
  `~/.bashrc` + `~/.bash_profile`), which source the managed setup under
  `~/.local/share/omarchy-nixos/`; the menu extension; user-dirs.dirs.
  Seeded when missing, refreshed from the default only while identical to
  the last seeded copy (`~/.local/state/omarchy/seeded/`), never overwritten
  once edited; an old store link (HM's) becomes a copy (`adopt`, off for
  the generated ones: the HM zshrc, the old menu layer); skipped when the
  host manages the path itself. A copy a user made in `~/.local/state/hypr`
  (which hyprland.lua's package.path loads first) moves to `~/.config/hypr`
  while that one is untouched, else it keeps winning with a warning.
  hyprland.lua loads: Omarchy's defaults, cursor env, keyboard layout,
  dropped binds, `omarchy.keybinds`, `extraConfig`, then the user's files,
  then toggles. The menu's Setup > Monitors/Input/Keybindings and Style >
  Hyprland are upstream's entries again. Monitor scale set by Omarchy's own
  command persists in monitors.lua (the "scale back to 2 after a rebuild"
  report: there was no monitors.lua, so the runtime scale was lost at the
  next config reload).
- **The NixOS menu layer is in the package** (appended to
  `default/omarchy/omarchy-menu.jsonc`, a repeated id replaces the entry in
  place); `~/.config/omarchy/extensions/omarchy-menu.jsonc` is the user's.
- **Themes switch live**: omarchy-theme-set records theme.json and runs
  upstream's own switcher (kept as `share/omarchy/libexec/omarchy-theme-set`,
  its `cp -r` from the store made writable). `current/theme` and
  `theme.name` are no longer HM-managed; activation (`omarchyTheme`) puts
  theme.json's theme there when that changed since the last activation
  (stamp `current/theme.json.name`), when its own link points at an older
  render, or when it's missing. Only the browser color policy and
  `omarchy.theme` wait for a rebuild. omarchy-theme-set-gnome uses dconf
  (no GSettings schemas on NixOS's search path).
- **dconf**: the GNOME interface keys (dark/light, GTK and icon theme,
  cursor) are a NixOS system dconf database without locks, not HM
  `dconf.settings` re-applied on every activation.
- **Cursor**: `omarchy.cursor.{enable,package,name,size}` (NixOS and HM;
  Bibata-Modern-Classic 24): HM `home.pointerCursor` (gtk, x11,
  hyprcursor) at mkDefault, XCURSOR_*/HYPRCURSOR_* in hyprland.lua (from
  the effective home.pointerCursor), the dconf default, SDDM's
  CursorTheme and its greeter Hyprland's env.
- **Keyboard**: `omarchy.keyboard.{layout,variant}` (the NixOS module passes
  services.xserver.xkb), set in hyprland.lua before input.lua, with
  upstream's non-Latin rule ("us," first). Upstream reads XKBLAYOUT from
  /etc/vconsole.conf, which NixOS doesn't write.
- **Default apps are opt-outs** (`lib.catalog.defaultApps`,
  `omarchy.defaultApps.<id>.enable`): their binds (Nautilus', btop's), MIME
  defaults and configs go with them; `omarchy.terminal` / `omarchy.browser`
  (desktop ids) become the package's xdg-terminals list and http(s)
  handlers. `omarchy.shell = "bash"` installs and configures no zsh.
- **Time zone**: `omarchy-menu-timezone` (NixOS edition) uses timedatectl
  through polkit when `time.timeZone` is null; the NixOS module writes
  /etc/omarchy/time-zone when it's set, and the entry says to change it in
  the config. Update > Time is upstream's.
- **Install > Package after a rebuild**: the menu's actions run inside the
  omarchy-shell unit's cgroup; a rebuild that restarts the shell (package
  or theme changed) killed the wrapper's terminal mid-rebuild and the stop
  stalled on its root-owned sudo ("Failed to kill control group"). The unit
  now has `KillMode=process`. The report "the wrapper no longer opens" was
  not reproduced: in the VM it opens again after the rebuild, before and
  after this change.

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

## Shell plugins (2026-09-27)

Upstream's third-party shell plugins (`omarchy plugin add/update/remove/
enable/disable/clone/list/validate`, Setup > Plugins; manual
32-shell-plugins.md) work on this flake as on Arch, plus:

- **What upstream's commands needed:** git and ripgrep on PATH (runtime
  deps, low priority), gum, jq, find, inotifywait were there. The plugin
  directory `~/.config/omarchy/plugins` is the user's (the shell creates
  it); nothing manages it except declared plugins' links.
- **Arch paths** (NixOS module, both default on): `omarchy.envfs.enable`
  (`services.envfs`: /usr/bin and /bin resolve from the calling process's
  PATH; the fallback dir has env, sh and bash) and `omarchy.usrShare.enable`
  (tmpfiles links /usr/share/omarchy → the first desktop user's package,
  /usr/share/zoneinfo → /etc/zoneinfo). envfs and the shell: Quickshell's
  children exec with the omarchy-shell unit's PATH (the user profile,
  wrappers, system), so /usr/bin/python3 and /usr/bin/omarchy-* work. A
  process that clears its environment (`PATH=/usr/bin`, My Journal does)
  still resolves: envfs tries the execve's PATH, then the process's
  original environment. A command on no PATH stays missing; `ls /usr/bin`
  lists nothing. VM-tested (checks.plugins).
- **QML modules:** plugins import Qt5Compat.GraphicalEffects (12 files in
  the 300-plugin sample) and QtMultimedia (16); `omarchy.qmlModules` (HM,
  default qt5compat + qtmultimedia from nixos-unstable, Quickshell's Qt)
  puts them on the shell's QML_IMPORT_PATH/QT_PLUGIN_PATH. QtWebEngine and
  Qt.labs.lottieqt (one plugin each) aren't there.
- **python3** in the runtime deps is low priority, so a
  `python3.withPackages` from a plugin's packages (or the host) wins.
- **`omarchy plugin doctor [id|path ...] [--json]`**
  (`pkgs/plugin-doctor.nix`, installed over the package's commands with its
  `# omarchy:` metadata so `omarchy plugin doctor` routes): static analysis
  of a plugin's files (QML/JS command arrays, `sh -c` strings, its shell
  and Python scripts reachable from the UI, shebangs, /usr/bin paths;
  dev/install scripts nothing references are skipped), against the shell
  unit's PATH. Names packages from nixpkgs' programs.sqlite (the channel's
  command-not-found DB, fetched from the pinned 26.05 channel release:
  same release as the flake, top-level attributes, 16 MB; chosen over
  nix-index-database, which is ~10x larger, follows unstable and answers
  with sub-attributes), NixOS options for commands that come with a service
  or driver (fprintd, nvidia-smi, tailscale, …), python3Packages for
  imports (a list of attribute names built in), QML modules the shell
  can't load, fixed paths, pacman/AUR use (Arch-only) and native builds.
  Without the DB it says so and still lists what's missing.
- **Declared plugins:** `omarchy.plugins.<id>` (HM, and NixOS passing to
  every user): `src` or `url`+`rev`+`hash` (fetchgit), `enable`,
  `section`, `packages`. Built with lib.mkPlugin (copied as cloned, .git
  dropped, validated, manifest id must match), linked at
  `~/.config/omarchy/plugins/<id>` (HM xdg.configFile; a real dir there
  from `omarchy plugin add` makes HM stop with "in the way"). Switched on
  through upstream's shell.json rules: into the package's default
  shell.json (used while the user has none), and by activation once into
  an existing user shell.json (state in
  `~/.local/state/omarchy/plugins.json`); the user switching it off or
  moving it sticks; undeclared → switched off. The shell restarts when the
  set changes (the package changes). An entry with only `packages` serves
  an imperatively added plugin (what the doctor prints).
- **lib.catalog.plugins** ("picked"): Moon Arc, My Journal, Mouse battery,
  pinned, `attrs` = packages, `url`/`rev`/`hash`/`kind` for the
  Configurator (not changed there yet: it'd show a "Shell plugins" group
  and write `omarchy.plugins.<id>`). checks.catalog-plugins builds them.
- **Tests:** checks.plugins (VM: declared plugin from the NixOS module,
  `omarchy plugin add --yes --enable` of local git repos, bar geometry,
  no QML errors naming them, #!/usr/bin/python3 and PATH=/usr/bin
  python through envfs, /usr/share/omarchy, the doctor on setxkbmap- and
  yay-using plugins, a user's disable surviving re-activation, removal),
  checks.plugins-shell-json, checks.plugin-doctor, checks.catalog-plugins.
  The VM draws in software: reloading plugins can take longer than
  omarchy-shell's 2 s IPC timeout, so the tests set
  OMARCHY_SHELL_IPC_TIMEOUT=20s.
- **Survey** (scripts/plugin-survey, README there): clones the catalog's
  installable plugins (3,668), validates, runs the doctor, then adds each
  in logged-in VMs in batches with the doctor's packages and records
  load/errors/crash/screenshot into results.jsonl. First run
  (2026-09-27): 20 random from the 300 sample: 17 work as is, 3 Arch-only
  (two menu forks carrying pacman calls load fine; system-pulse's widget
  fails: C helper + missing omarchy-system-monitor); 7 picked for packages:
  6 load with what the doctor named (setxkbmap, poppler-utils+libarchive,
  glib, pillow, services.fprintd), kefctl is Arch-only (its kefctl isn't
  in nixpkgs). ~10 s per plugin, ~2.5 min per 10-plugin boot.
- **Survey harness fixes (2026-09-28)**, after reviewers found the
  harness at fault for about a quarter of "fails to load": the plugin is
  found by its manifest id (7 catalog ids differ); journal lines are matched
  for error words without the plugin's ids and file URLs and never at
  DEBUG (ids with "mirror" hit "rror"); FileView's missing state files and
  images that exist a moment later are `warnings`, not errors; the VM's
  user stays awake (Omarchy's stay-awake state file via
  `xdg.stateFile`, no screensaver at 150 s or lock at 300 s mid-batch);
  8 GB VM disk and each plugin's copies deleted; replacement bars and
  lock-screen/background-layer plugins run last in their batch with the
  shell restarted after each. Proof batch: 30 plugins, 442 s, never locked,
  widgets after two replacement bars got slots. Rerun of the 281 plugins
  that were fails-to-load or bar widgets run after a replacement bar:
  111 of 220 fails-to-load now load (76 as is, 35 with packages), 109
  still fail, every one on QML errors naming it (no missing slots, no
  locks); the others kept their category. Survey now (3,618): 2,421 work
  as is, 608 with packages, 263 Arch-only, 202 native build, 109 fail to
  load, 15 clone failed.
- **Upstream bug (confirmed): removing a replacement bar leaves no bar
  API.** shell.qml's `pluginBarLoader` has `onActiveChanged: if (!active)
  shell.bar = null`; switching back to the default bar loads
  `defaultBarLoader` (whose `onLoaded` sets `shell.bar`) before the plugin
  loader's handler runs, so `shell.bar` ends null (the default loader's
  own handler guards with `shell.activeBarId !== shell.defaultBarId`; the
  plugin one doesn't). The default bar is loaded, but
  `debugBarGeometry` is `[]` and everything bound to `shell.bar` (the
  plugin bar API's barSize, position, font) falls back until the shell
  restarts. Seen in the survey VM: 0 slots right after removing
  charlieras262.floating-bar and grechman.dynamic-bar, every widget back
  after a restart. A reviewer found the same code in upstream's newest
  `quattro`. Fix upstream: the same guard on the plugin loader.
- **Packaged plugins and helpers (2026-09-28).** Reviewers found the
  blocker for native-build plugins is *where* helpers are looked for
  (`<plugin>/bin/x`, `~/.local/bin/x`, a venv path, a download), not
  building them. `omarchy.plugins.<id>` gained `helpers` (rel path →
  file, copied into the plugin's store tree, dereferenced: the validator
  refuses symlinks, and it validates after they're in), `home`
  (`home.file` links: `~/.local/bin/x`, a venv dir = a
  `python3.withPackages`), `patches`/`postPatch` (the plugin's files),
  `hyprlandPlugins` + `hyprlandConfig` (loaded with `hl.plugin.load` at
  the top of the generated hyprland.lua; `omarchy.hyprland.plugins`,
  built against `omarchy.hyprland.package`, which the NixOS module sets
  to `programs.hyprland.package`), `qmlModules`, and `registry`.
  **The registry** (`pkgs/plugins/<id>/default.nix`, auto-discovered, so
  parallel agents add entries without touching shared files): each entry
  is `lib.callPackageWith` over 26.05 + `omarchyUnstable` (Quickshell's
  Qt), `hyprland`, `mkHyprlandPlugin` (unstable's, `.override { hyprland
  }`), returning `src` (fetchFromGitHub at the survey's commit) and the
  attrs above. A declaration without `src`/`url` whose id is in the
  registry uses the entry (its attrs first, the declaration's added);
  `registry = false` keeps a hand-added plugin with only `packages`.
  Exposed as `legacyPackages.<system>.plugins."<id>"` (`.home`: the
  home links as a tree, `.entry`) and `lib.plugins` (data: url, rev,
  hash, helper/home paths, package names; for the Configurator).
  `omarchy plugin add` prints how to declare a registry plugin (a
  sed-inserted note after it reads the id; ids baked into the package).
  Examples: io.github.bitshiftxr.atrium (Rust `bin/atriumd`, its
  `/usr/bin/secret-tool` patched to the store), io.github.lolu13.onote
  (Rust at `~/.local/bin/onote-helper`, wl-clipboard paths patched, two
  tests skipped that exec /usr/bin/cat), seigliva.ha-watch (python3 +
  aiohttp at `~/.local/share/seigliva.ha-watch/venv`). checks.plugin-registry
  declares every entry in one home and checks helpers, links, shell.json
  and the plugin load line.
- **Flake-wide fixes from the reviews (2026-09-28):** `omarchy.nixLd.enable`
  (NixOS, default on: nix-ld was already on for Mason/mise; adds libevdev,
  pipewire, libpulseaudio, dbus, curl, openssl, zlib, glib, libxkbcommon,
  wayland, libstdc++ to nix-ld's defaults, for the 13 "ldd" plugins'
  shipped/downloaded binaries); `omarchy.qmlModules` default + qtwebsockets,
  qtpositioning, qtlottie, qtquick3d (~50 MB over qtdeclarative; Qt.labs.platform
  is already in qtdeclarative), `omarchy.qtWebEngine.enable` (opt-in, ~600
  MB); ruby and sqlite low-priority runtime deps; envfs' fallback dir has
  coreutils and setsid (processes with a cleared environment:
  agents-usage); `/usr/share/fonts` (buildEnv of fonts.packages + the first
  user's home.path, share/fonts only: Arch's `noto/…` layout) and
  `/usr/share/pixmaps/omarchy.png`; `omarchy.usrShare.voxtype` (default
  off) links `/usr/share/voxtype/quickshell` from nixos-unstable voxtype's
  **source** (1.0.1 has quickshell/voxtype-shared; no nixpkgs voxtype
  installs it, 26.05's 0.7.2 source predates it).
  Survey (2026-09-28, the 3 examples + 7 "ldd" + 7 "nixos" plugins):
  atrium, onote, ha-watch load declared ("works packaged"; atrium's
  "Process failed to start … bin/atriumd" is gone); newgrounds-radio and
  bitfinex-ticker (QtWebSockets), omarchy-wallpapers (pixmaps) and omaflow
  (ruby) now load; the ldd plugins load (their binaries aren't exercised by
  the survey); changing-lines still fails: /usr/share/fonts is there but
  NotoSansSymbols2 is in `noto-fonts`, which the desktop doesn't install
  (the plugin's `packages = [ pkgs.noto-fonts ]` would do, the link includes
  the user's fonts); agents-usage's remaining error is its own (assets/*.png
  that are .svg in the repo).
- **Unsolved:** pacman/yay/paru plugins (update checkers, package menus);
  native builds not in the registry yet (C/C++/Rust helpers, compiled QML plugins, `npm install`,
  prebuilt binaries); commands nixpkgs lacks (kefctl, voxtype-audio-bridge,
  herdr from nixpkgs, …); fixed paths beyond /usr/bin, /bin,
  /usr/share/omarchy and zoneinfo (/usr/lib/qt6/bin, /usr/share/icons,
  /usr/share/fonts/TTF/…, /opt); processes started with no PATH that has
  the command; plugins whose install scripts do setup (systemd units,
  udev rules, sudo) that `omarchy plugin add` never runs anyway; the
  doctor is heuristic (dynamic command strings aren't seen; a few English
  words in shell text can look like commands and are only reported when a
  package of that exact name exists).

