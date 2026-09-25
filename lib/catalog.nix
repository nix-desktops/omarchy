# What Omarchy on NixOS can install, as data, grouped as PACKAGES.md decides
# (that file is the source of truth; keep this in step with it). The Home
# Manager module installs from it, and the flake exports it (`lib.catalog`)
# so an installer can list each group, preselect what's on and write back
# the ids the user keeps.
#
#   layers.<group>   who turns the group on: "default" (with the desktop,
#                    per-program opt-outs), "ecosystem" (the "Install entire
#                    ecosystem" switch, `omarchy.ecosystem.enable`) or
#                    "picked" (only what the user lists)
#
# Each entry:
#   name, description   for the installer
#   attrs               nixpkgs attributes it installs ("unstable.<attr>":
#                       from nixos-unstable; "omarchy.<name>": this flake's
#                       packages of Omarchy's own tools; [ ] = nothing)
#   packaged            false while it isn't in nixpkgs yet (skipped, with
#                       its binds and launchers, until it is)
#   preinstalled        installed with its group (false: bound, installed on
#                       first use of the bind, as upstream does)
#   binds               upstream key combos that belong to it
#   launchers, icons    desktop files and icons from upstream's applications/
#   command             (agents) the command it runs as
#
# The keybinds are upstream's, from `packages.<system>.keybinds`;
# `checks.catalog` fails when upstream adds an app or web-app bind that no
# entry here covers, or drops one an entry still lists.
let
  entry = attrs: {
    description = "";
    attrs = [ ];
    packaged = true;
    preinstalled = true;
    binds = [ ];
    launchers = [ ];
    icons = [ ];
  } // attrs;


  tool = name: attr: description: entry { inherit name description; attrs = [ attr ]; };

  webapp = name: url: attrs: entry ({ inherit name url; } // attrs);
in
{
  layers = {
    cli = "default";
    tuis = "default";
    apps = "ecosystem";
    webapps = "ecosystem";
    development = "ecosystem";
    agents = "picked";
    tools = "picked";
  };

  # -------------------------------------------------- CLI setup (default)
  # Installed with the desktop, each one opt-out (`omarchy.cli.<id>.enable`).
  # man-db and plocate are the NixOS module's (documentation, services.locate).
  cli = {
    bat = tool "bat" "bat" "cat with syntax highlighting";
    eza = tool "eza" "eza" "ls with icons and git status";
    fd = tool "fd" "fd" "Fast find";
    fzf = tool "fzf" "fzf" "Fuzzy finder";
    ripgrep = tool "ripgrep" "ripgrep" "Fast grep";
    zoxide = tool "zoxide" "zoxide" "Smarter cd";
    starship = tool "Starship" "starship" "Shell prompt";
    tmux = tool "tmux" "tmux" "Terminal multiplexer";
    lazygit = tool "lazygit" "lazygit" "Git in the terminal";
    less = tool "less" "less" "Pager";
    tldr = tool "tldr" "tldr" "Short command examples";
    inxi = tool "inxi" "inxi" "System information";
    whois = tool "whois" "whois" "Domain lookup";
    unzip = tool "unzip" "unzip" "Zip archives";
    dua = tool "dua" "dua" "Disk usage";
    git = tool "Git" "git" "Version control";
    vi = tool "vi" "nvi" "The classic vi";
    bash-completion = tool "bash-completion" "bash-completion" "Completions for bash";
    tree-sitter = tool "tree-sitter" "tree-sitter" "Parser generator (Neovim)";
  };

  # ------------------------------------------------ TUI launchers (default)
  # Opt-out each (`omarchy.tuis.<id>.enable`); their binds go with them.
  tuis = {
    lazydocker = entry {
      name = "Docker";
      description = "lazydocker in a terminal (the Docker daemon is the development layer)";
      attrs = [ "lazydocker" ];
      binds = [ "SUPER + SHIFT + D" ];
      launchers = [ "Docker.desktop" ];
      icons = [ "Docker.png" ];
    };
    disk-usage = entry {
      name = "Disk Usage";
      description = "dua in a floating terminal";
      attrs = [ "dua" ];
      launchers = [ "Disk Usage.desktop" ];
      icons = [ "Disk Usage.png" ];
    };
    tmux = entry {
      name = "Tmux";
      description = "A terminal with a tmux session";
      attrs = [ "tmux" ];
      binds = [ "SUPER + ALT + RETURN" ];
    };
  };

  # ------------------------------------------------ opinionated apps (ecosystem)
  apps = {
    aether = entry { name = "Aether"; description = "Visual theme designer for Omarchy"; attrs = [ "omarchy.aether" ]; };
    cliamp = entry { name = "Cliamp"; description = "Music player for the terminal"; attrs = [ "cliamp" ]; binds = [ "SUPER + SHIFT + ALT + M" ]; };
    libreoffice = tool "LibreOffice" "libreoffice-fresh" "Office suite";
    xournalpp = tool "Xournal++" "xournalpp" "Handwriting and PDF annotation";
    pinta = tool "Pinta" "pinta" "Image editor";
    obsidian = entry { name = "Obsidian"; description = "Markdown notes"; attrs = [ "obsidian" ]; binds = [ "SUPER + SHIFT + O" ]; };
    obs-studio = tool "OBS Studio" "obs-studio" "Screen recording and streaming";
    kdenlive = tool "Kdenlive" "kdePackages.kdenlive" "Video editor";
    moonlight = tool "Moonlight" "moonlight-qt" "Game streaming client";
    omacut = entry { name = "Omacut"; description = "Video cutter"; attrs = [ "omarchy.omacut" ]; };
    omacalc = entry { name = "Omacalc"; description = "Calculator"; attrs = [ "omarchy.omacalc" ]; };
    omawrite = entry {
      name = "Omawrite";
      description = "Distraction-free writing (with the iA Writer fonts)";
      attrs = [ "omarchy.omawrite" "ia-writer-duospace" "ia-writer-quattro" "ia-writer-mono" ];
      binds = [ "SUPER + SHIFT + W" ];
    };
    herdr = entry { name = "Herdr"; description = "Terminal workspace manager for AI coding agents"; attrs = [ "omarchy.herdr" ]; binds = [ "SUPER + CTRL + RETURN" ]; };
    tobi-try = entry { name = "try"; description = "Fresh directories for every experiment"; attrs = [ "omarchy.tobi-try" ]; };
    yt-dlp = tool "yt-dlp" "yt-dlp" "Video downloader";
    # Bound, installed on first use, as upstream does.
    spotify = entry { name = "Spotify"; description = "Music streaming"; attrs = [ "spotify" ]; preinstalled = false; binds = [ "SUPER + SHIFT + M" ]; };
    signal = entry { name = "Signal"; description = "Private messenger"; attrs = [ "signal-desktop" ]; preinstalled = false; binds = [ "SUPER + SHIFT + G" ]; };
    "1password" = entry { name = "1Password"; description = "Password manager"; attrs = [ "_1password-gui" ]; preinstalled = false; binds = [ "SUPER + SHIFT + SLASH" ]; };
  };

  # ------------------------------------------------------ web apps (ecosystem)
  # Open in the default (Chromium-based) browser as app windows.
  webapps = {
    hey = webapp "HEY" "https://app.hey.com" {
      description = "Email and calendar (also the mailto: handler)";
      launchers = [ "HEY.desktop" ];
      icons = [ "HEY.png" ];
      binds = [ "SUPER + SHIFT + E" "SUPER + SHIFT + ALT + E" "SUPER + SHIFT + C" ];
    };
    basecamp = webapp "Basecamp" "https://launchpad.37signals.com" { launchers = [ "Basecamp.desktop" ]; icons = [ "Basecamp.png" ]; };
    chatgpt = webapp "ChatGPT" "https://chatgpt.com" { binds = [ "SUPER + SHIFT + A" ]; icons = [ "ChatGPT.png" ]; };
    grok = webapp "Grok" "https://grok.com" { binds = [ "SUPER + SHIFT + ALT + A" ]; };
    youtube = webapp "YouTube" "https://youtube.com/" { launchers = [ "YouTube.desktop" ]; icons = [ "YouTube.png" ]; binds = [ "SUPER + SHIFT + Y" ]; };
    whatsapp = webapp "WhatsApp" "https://web.whatsapp.com/" { launchers = [ "WhatsApp.desktop" ]; icons = [ "WhatsApp.png" ]; binds = [ "SUPER + SHIFT + ALT + G" ]; };
    google-messages = webapp "Google Messages" "https://messages.google.com/web/conversations" { launchers = [ "Google Messages.desktop" ]; icons = [ "Google Messages.png" ]; binds = [ "SUPER + SHIFT + CTRL + G" ]; };
    google-photos = webapp "Google Photos" "https://photos.google.com/" { launchers = [ "Google Photos.desktop" ]; icons = [ "Google Photos.png" ]; binds = [ "SUPER + SHIFT + P" ]; };
    google-maps = webapp "Google Maps" "https://maps.google.com" { launchers = [ "Google Maps.desktop" ]; icons = [ "Google Maps.png" ]; binds = [ "SUPER + SHIFT + S" ]; };
    google-contacts = webapp "Google Contacts" "https://contacts.google.com/" { launchers = [ "Google Contacts.desktop" ]; icons = [ "Google Contacts.png" ]; };
    x = webapp "X" "https://x.com/" { launchers = [ "X.desktop" ]; icons = [ "X.png" ]; binds = [ "SUPER + SHIFT + X" "SUPER + SHIFT + ALT + X" ]; };
    zoom = webapp "Zoom" "https://app.zoom.us/wc/home" { description = "Also the zoommtg: link handler"; launchers = [ "Zoom.desktop" ]; icons = [ "Zoom.png" ]; };
    discord = webapp "Discord" "https://discord.com/channels/@me" { launchers = [ "Discord.desktop" ]; icons = [ "omarchy-discord.png" ]; };
  };

  # ------------------------------------------ developer tooling (ecosystem)
  # PACKAGES.md group 8. Upstream's development libraries
  # (mariadb/postgresql clients, libyaml, python-gobject, poetry-core) aren't
  # listed: on NixOS they come from the per-project dev environments
  # (Install > Development). Docker itself is the NixOS module's
  # `omarchy.development.enable`.
  development = {
    mise = tool "mise" "mise" "Per-project tool versions";
    usage = tool "usage" "usage" "CLI spec tool (mise completions)";
    clang = tool "Clang" "clang" "C/C++ compiler";
    ruby = tool "Ruby" "ruby" "Ruby";
    lua = tool "Lua 5.1" "lua5_1" "Lua (Neovim plugins)";
    luarocks = tool "LuaRocks" "luarocks" "Lua packages";
    dotnet-runtime = tool ".NET runtime" "dotnet-runtime" ".NET apps";
    docker-compose = tool "Docker Compose" "docker-compose" "Multi-container Docker";
    docker-buildx = tool "Docker Buildx" "docker-buildx" "Docker build extensions";
  };

  # ------------------------------------------------ AI agents (picked)
  # Never on by default or with the ecosystem: `omarchy.agents` and
  # `omarchy.defaultAgent`. Ids are upstream's agent names, as
  # omarchy-default-agent and the Setup > Defaults > Agent menu use them.
  # Only agents that build are listed: upstream's omp, ori, hermes and muse
  # aren't in nixpkgs, and openclaw is marked insecure there (the menu hides
  # them).
  agents = {
    pi = entry { name = "Pi"; attrs = [ "pi-coding-agent" ]; command = "pi"; };
    opencode = entry { name = "OpenCode"; attrs = [ "opencode" ]; command = "opencode"; };
    claude = entry { name = "Claude Code"; attrs = [ "claude-code" ]; command = "claude"; };
    codex = entry { name = "Codex"; attrs = [ "codex" ]; command = "codex"; };
    crush = entry { name = "Crush"; attrs = [ "crush" ]; command = "crush"; };
    grok = entry { name = "Grok"; attrs = [ "grok-cli" ]; command = "grok"; };
    agy = entry { name = "Antigravity"; attrs = [ "unstable.antigravity-cli" ]; command = "agy"; };
    copilot = entry { name = "GitHub Copilot"; attrs = [ "github-copilot-cli" ]; command = "copilot"; };
    cursor-agent = entry { name = "Cursor CLI"; attrs = [ "cursor-cli" ]; command = "cursor-agent"; };
  };

  # ------------------------------------------- CLIs next to the agents (picked)
  # `omarchy.tools`. Only those that build: upstream's cf, hey-cli and
  # basecamp-cli aren't in nixpkgs, and nixpkgs' ghui doesn't build.
  tools = {
    gh = tool "GitHub CLI" "gh" "GitHub from the terminal";
    playwright = tool "Playwright" "playwright-test" "Browser automation";
    hunk = tool "hunk" "unstable.hunk" "Diff viewer for agent changesets";
  };
}
