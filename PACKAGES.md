# What this desktop installs

The user's decision (2026-09-25) on what Omarchy on NixOS installs **by
default**, what belongs to **Omarchy's ecosystem** (the configurator's
"Install entire ecosystem" checkbox, `omarchy.ecosystem.enable`) and what the
user **picks in the configurator UI**. This is the source of truth for
`modules/home/apps.nix` (defaults), `lib/ecosystem.nix` (ecosystem) and the
NixOS module. When the code disagrees with this file, the code is wrong.

Inventory taken from upstream `basecamp/omarchy` `quattro` at `93e8cd5`
(`install/omarchy-base.packages`, `bin/omarchy-install-preinstalls`,
`applications/*.desktop`, `default/hypr/bindings/applications.lua`,
`install/user/mise.sh`). Re-check it when upstream changes those files.

| # | Group | Decision |
|---|-------|----------|
| 1 | Integrated into Omarchy | **Default** |
| 2 | Default apps (terminal, browser, files, editor, viewers) | **Default** |
| 3 | CLI setup | **Default** |
| 4 | Opinionated apps | **Ecosystem** |
| 5 | Web apps | **Ecosystem** |
| 6 | TUI launchers | **Default** |
| 7 | AI agents and CLIs | **Picked in the configurator UI** (none by default, not part of the ecosystem) |
| 8 | Developer tooling | **Ecosystem** (`development` layer) |
| 9 | Arch-only | **Not installed** (NixOS has its own equivalents) |

## 1. Integrated into Omarchy (default)

Omarchy's features, commands and keybinds depend on these.

- **Desktop core:** hyprland, hyprland-guiutils, hyprland-preview-share-picker,
  uwsm, xdg-desktop-portal-hyprland, xdg-desktop-portal-gtk, quickshell,
  qt6-imageformats, plymouth, sddm, yaru-icon-theme, gnome-themes-extra.
- **Omarchy's own tools:** omasnap (screenshots), ttfx (screensaver),
  owe + owe-lockfeed (video wallpapers, lock-screen feed), elsewhen (bar
  widget). Not in nixpkgs yet; see HANDOFF item 6 (until then: hyprshot +
  satty, tte).
- **Shell features:** hyprpicker, hyprsunset, grim, slurp,
  gpu-screen-recorder, v4l-utils (webcam overlay), tesseract (OCR), zbar
  (QR), qrencode (Wi-Fi QR), wl-clipboard, wtype, imagemagick, libvips,
  ffmpeg + ffmpegthumbnailer, socat, jq, gum, inotify-tools,
  xdg-terminal-exec, pciutils and psmisc (lspci, killall: hardware checks,
  terminal restarts).
- **Hardware and services behind the panels:**
  - audio: wireplumber, pamixer, alsa-utils
  - display and power: brightnessctl, ddcutil, asdcontrol,
    power-profiles-daemon
  - connectivity: networkmanager, bluez (+ tools), bolt (Thunderbolt)
  - storage: udiskie, dosfstools, exfatprogs
  - integrations: localsend, gnome-keyring + libsecret, fcitx5, avahi +
    nss-mdns, cups + cups-filters + cups-pk-helper + system-config-printer
- **Fonts:** JetBrains Mono Nerd, Noto (+ CJK, emoji), Font Awesome.

## 2. Default apps (default)

One app per role, as Omarchy's keybinds and MIME defaults expect.

- **Terminal:** foot (SUPER+RETURN). Alternatives via
  `omarchy-default-terminal`: alacritty, ghostty, kitty.
- **Browser:** Chromium (SUPER+SHIFT+B). Web apps need a Chromium-based
  browser.
- **File manager:** Nautilus + sushi + nautilus-python + gvfs (mtp, nfs,
  smb) (SUPER+SHIFT+F).
- **Editor:** Neovim with `omarchy-nvim` (SUPER+SHIFT+N).
- **Viewers:** imv (images), mpv + mpv-mpris (media), evince (PDF).
- **System tools:** btop, fastfetch, gnome-disk-utility.

## 3. CLI setup (default)

Installed with Omarchy's configs for them (HANDOFF item 5, ported to zsh):

bat, eza, fd, fzf, ripgrep, zoxide, starship, tmux, lazygit, less, man-db,
tldr, plocate, inxi, whois, unzip, dua, git, vi, bash-completion,
tree-sitter-cli.

## 4. Opinionated apps (ecosystem)

- **Upstream's preinstalls:** aether, cliamp, libreoffice-fresh, xournalpp,
  pinta, obsidian, obs-studio, kdenlive, moonlight-qt, omacut, omacalc,
  omawrite (+ the ttf-ia-writer font). lazydocker is also an upstream
  preinstall, but it's the Docker launcher's app (group 6), so it's a default.
- **Other opinionated picks in upstream's base:** herdr, tobi-try, yt-dlp.
- **Bound, installed on first use:** Spotify (SUPER+SHIFT+M), Signal
  (SUPER+SHIFT+G), 1Password (SUPER+SHIFT+/).
- Their keybinds (upstream's `preinstalled_bindings`) come with them.

## 5. Web apps (ecosystem)

- **Launchers (`applications/`):** Basecamp, Discord, Google Contacts, Google
  Maps, Google Messages, Google Photos, HEY (the mailto: handler), WhatsApp,
  X, YouTube, Zoom (the zoommtg: handler).
- **Keybind only:** ChatGPT (SUPER+SHIFT+A), Grok, HEY Calendar, new email,
  X post.

## 6. TUI launchers (default)

- **Disk Usage** (dua, in a floating terminal).
- **Docker** (lazydocker). The Docker daemon itself goes with group 8.

## 7. AI agents and CLIs (configurator UI)

Not installed by default and **not** switched on by the ecosystem checkbox:
the user picks them in the configurator (or sets the options by hand). The
agent integration (the shell's agents panel, SUPER+SHIFT+CTRL+A picker, the
scratchpad console, Setup > Defaults > Agent) is part of group 1 and always
on.

- **Agents** (`omarchy.agents`, `omarchy.defaultAgent`; HANDOFF item 4):
  codex, claude, crush, antigravity (agy), copilot, opencode, pi, oh-my-pi
  (omp), grok, cursor-agent, ori, hermes, muse.
- **CLIs** upstream installs next to them: gh, playwright, ghui, hunk, cf,
  hey-cli, basecamp-cli.

## 8. Developer tooling (ecosystem)

docker, docker-buildx, docker-compose, mise, usage, clang, llvm, ruby,
lua 5.1, luarocks, dotnet-runtime, mariadb and postgresql client libraries,
python-gobject, python-poetry-core, libyaml. On NixOS the per-language
toolchains come from the nix-templates/dev environments (Install >
Development). The user's decision: it stays the ecosystem's `development`
layer.

## 9. Arch-only (not installed)

yay, pacman-contrib, expac, kernel-modules-hook, fakeroot, ufw + ufw-docker
(the NixOS firewall instead), tzupdate (`services.automatic-timezoned`),
wireless-regdb and qemu-user-static-binfmt (NixOS options), inetutils.

## Where the code stands (2026-09-25)

The code matches this file: `lib/catalog.nix` holds every group as data
(`lib.catalog`, with `layers` saying which is default, ecosystem or picked),
`modules/home/catalog.nix` installs it, `modules/home/apps.nix` holds the
default apps, `modules/home/shell.nix` the CLI setup.

**What doesn't build is left out** (the user's decision): the agents omp,
ori, hermes and muse and the CLIs cf, hey-cli and basecamp-cli (not in
nixpkgs), openclaw (marked insecure in nixpkgs), ghui (nixpkgs' package
doesn't build), and from group 1 `asdcontrol` and `hyprland-guiutils` (not in
nixpkgs). The menu hides the agents that can't be picked.
