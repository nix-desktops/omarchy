# The NixOS layer over Omarchy's menu, deployed as
# ~/.config/omarchy/extensions/omarchy-menu.jsonc.
#
# The shell normalizes every extension entry (missing fields become "",
# the label becomes the id) and then replaces the shipped entry with it, so
# an extension entry has to be complete. The overrides below are therefore
# merged onto upstream's own entries here, from default/omarchy/
# omarchy-menu.jsonc in the pinned `omarchy` input, and written out whole:
# icons, labels and actions carry over, and the build fails if any visible
# entry would end up without an icon.
#
# - Installs are declarative: `omarchy-pkg-install <nixpkgs attr>` adds to
#   the host's apps.json and rebuilds; guards use omarchy-pkg-present
#   with the same attribute.
# - Entries with no NixOS equivalent (AUR, Plymouth, release channels,
#   runtime /etc edits, …) are hidden with `when = "false"`.
{ lib, omarchy }:
let
  # Omarchy's JSONC: whole-line // comments and trailing commas (the same
  # two things the shell's stripJsonc removes).
  raw = builtins.readFile (omarchy + "/default/omarchy/omarchy-menu.jsonc");
  noComments = lib.concatStringsSep "\n"
    (builtins.filter (l: builtins.match "[[:space:]]*//.*" l == null) (lib.splitString "\n" raw));
  noTrailingCommas = lib.concatMapStrings (p: if builtins.isList p then builtins.head p else p)
    (builtins.split ",([[:space:]]*[]}])" noComments);
  upstream = builtins.fromJSON noTrailingCommas;

  # Nerd Font glyph from its codepoint. Private-use BMP glyphs get lost as
  # literal characters in some editors/tools, so they are spelled as escapes.
  g = hex: builtins.fromJSON "\"\\u${hex}\"";
  nixos = g "f313";

  term = cmd: "omarchy-launch-floating-terminal-with-presentation '${cmd}'";
  hide = { when = "false"; };
  install = attr: {
    disabled = "omarchy-pkg-present ${attr}";
    action = term "omarchy-pkg-install ${attr}";
  };
  remove = attr: {
    when = "omarchy-pkg-present ${attr}";
    action = term "omarchy-pkg-remove ${attr}";
  };
  # The host's NixOS config (omarchy.configDir): Hyprland, keybinds and
  # monitors are generated from it.
  editConfig = { action = "omarchy-launch-config-editor \"$OMARCHY_CONFIG\""; };
  scaffold = { disabled = "false"; };

  # Only the agents lib/catalog.nix can install can be picked.
  catalog = import ./catalog.nix;
  unpackagedAgents = lib.mapAttrs' (id: _: lib.nameValuePair id hide)
    (lib.filterAttrs (id: _: lib.hasPrefix "setup.default.agent." id
        && !(catalog.agents ? ${lib.removePrefix "setup.default.agent." id}))
      upstream);

  baseOverrides = {
    # ---- Learn -----------------------------------------------------------
    "learn.arch" = { icon = nixos; label = "NixOS"; action = "omarchy-launch-webapp 'https://nixos.org/manual/nixos/stable/'"; };
    "learn.nixpkgs" = { icon = "󰏖"; label = "Nixpkgs Search"; action = "omarchy-launch-webapp 'https://search.nixos.org/packages'"; };
    "learn.home-manager" = { icon = g "f015"; label = "Home Manager"; action = "omarchy-launch-webapp 'https://home-manager-options.extranix.com/'"; };

    # ---- Trigger ---------------------------------------------------------
    "trigger.hardware.hybrid-gpu" = hide;

    # ---- Style -----------------------------------------------------------
    # Upstream swaps the boot splash and login logos in /usr/share; here
    # the name they show goes into branding.json (omarchy.branding.name).
    "style.unlock" = {
      label = "Branding";
      aliases = [ "unlock" "branding" "name" ];
      action = term "omarchy-branding-name";
    };
    "style.hyprland" = editConfig;

    # ---- Setup -----------------------------------------------------------
    # Hyprland, keybinds and the monitor layout are generated from the
    # host's NixOS config.
    "setup.monitors" = editConfig;
    "setup.keybindings" = editConfig // { when = ""; };
    "setup.input" = hide;
    "setup.config.hyprland" = editConfig;
    "setup.config.repo" = { icon = g "e702"; label = "Config Repo"; action = "omarchy-launch-config-editor \"$OMARCHY_CONFIG\""; };
    "setup.config.lazygit" = { icon = "󰊢"; label = "Config Repo (lazygit)"; action = "xdg-terminal-exec --app-id=org.omarchy.terminal --dir=\"$OMARCHY_CONFIG\" lazygit"; };
    # Declared in the NixOS config instead: DNS (networking.nameservers),
    # fingerprint/FIDO2 (security.pam), sshd, sudo, the docker group.
    "setup.network.dns" = hide;
    "setup.security" = hide;
    "setup.direct-boot" = hide;
    "setup.reset" = hide;

    # ---- Install ---------------------------------------------------------
    "install.package" = { icon = nixos; };
    "install.aur" = hide;
    "install.windows" = hide;
    "install.preinstalls" = hide;

    "install.browser.chrome" = install "google-chrome";
    "install.browser.edge" = install "microsoft-edge";
    "install.browser.brave" = install "brave";
    "install.browser.brave-origin" = hide;
    "install.browser.firefox" = install "firefox";
    "install.browser.zen" = hide;

    "install.service.1password" = install "_1password-gui";
    "install.service.dropbox" = install "dropbox";
    "install.service.spotify" = install "spotify";
    "install.service.signal" = install "signal-desktop";
    "install.service.bitwarden" = install "bitwarden-desktop";
    # Tailscale is a NixOS service (services.tailscale), not a user package.
    "install.service.tailscale" = hide;
    "install.service.nordvpn" = hide;
    "install.service.once" = hide;

    "install.editor.vscode" = install "vscode";
    "install.editor.cursor" = install "code-cursor";
    "install.editor.zed" = install "zed-editor";
    "install.editor.sublime" = install "sublime4";
    "install.editor.helix" = install "helix";
    "install.editor.vim" = install "vim";
    "install.editor.emacs" = install "emacs";

    "install.terminal.alacritty" = install "alacritty";
    "install.terminal.foot" = install "foot";
    "install.terminal.ghostty" = install "ghostty";
    "install.terminal.kitty" = install "kitty";

    "install.ai.lm-studio" = install "lmstudio";
    "install.ai.ollama" = install "ollama";
    "install.ai.chatgpt" = hide;
    "install.ai.claude" = hide;
    "install.ai.dictation" = hide;
    "install.ai.grok-bot" = hide;
    "install.ai.hermes" = hide;
    "install.ai.openclaw" = hide;
    "install.ai.perplexity" = hide;
    "install.ai.t3-code" = hide;

    # Steam and controller drivers are NixOS options (programs.steam,
    # hardware.xpadneo), not user packages.
    "install.gaming.steam" = hide;
    "install.gaming.xbox-controllers" = hide;
    "install.gaming.retroarch" = install "retroarch";
    "install.gaming.minecraft" = install "prismlauncher" // { label = "Minecraft (Prism Launcher)"; };
    "install.gaming.lutris" = install "lutris";
    "install.gaming.heroic" = install "heroic";
    "install.gaming.geforce-now" = hide;
    "install.gaming.battlenet" = hide;
    "install.gaming.retro-launcher" = hide;

    # Development: each language scaffolds a new project with that devShell
    # (omarchy-install-dev-env → omarchy-dev-env), so none is ever
    # "installed" and the mise-based guards go.
    "install.development.all" = { icon = "󰅩"; label = "All Templates"; action = "omarchy-dev-env"; };
    "install.development.docker-dbs" = { action = "omarchy-install-docker-dbs"; };
    "install.development.rails" = scaffold;
    "install.development.go" = scaffold;
    "install.development.python" = scaffold;
    "install.development.zig" = scaffold;
    "install.development.rust" = scaffold;
    "install.development.java" = scaffold;
    "install.development.dotnet" = scaffold;
    "install.development.ocaml" = scaffold;
    "install.development.clojure" = scaffold;
    "install.development.scala" = scaffold;
    "install.development.javascript.node" = scaffold;
    "install.development.javascript.bun" = scaffold;
    "install.development.javascript.deno" = scaffold;
    "install.development.php.php" = scaffold;
    "install.development.php.laravel" = scaffold;
    "install.development.php.symfony" = scaffold;
    "install.development.elixir.elixir" = scaffold;
    "install.development.elixir.phoenix" = scaffold;

    # ---- Remove ----------------------------------------------------------
    "remove.package" = { icon = nixos; };
    "remove.development" = hide;
    "remove.windows" = hide;
    "remove.preinstalls" = hide;
    "remove.security" = hide;

    "remove.browser.chrome" = remove "google-chrome";
    "remove.browser.edge" = remove "microsoft-edge";
    "remove.browser.brave" = remove "brave";
    "remove.browser.brave-origin" = hide;
    "remove.browser.firefox" = remove "firefox";
    "remove.browser.zen" = hide;

    "remove.service.dropbox" = remove "dropbox";
    "remove.service.tailscale" = hide;

    "remove.ai.lm-studio" = remove "lmstudio";
    "remove.ai.ollama" = remove "ollama";
    "remove.ai.chatgpt" = hide;
    "remove.ai.claude" = hide;
    "remove.ai.dictation" = hide;
    "remove.ai.grok-bot" = hide;
    "remove.ai.hermes" = hide;
    "remove.ai.openclaw" = hide;
    "remove.ai.perplexity" = hide;
    "remove.ai.t3-code" = hide;

    "remove.gaming.steam" = hide;
    "remove.gaming.xbox-controllers" = hide;
    "remove.gaming.retroarch" = remove "retroarch";
    "remove.gaming.minecraft" = remove "prismlauncher" // { label = "Minecraft (Prism Launcher)"; };
    "remove.gaming.lutris" = remove "lutris";
    "remove.gaming.heroic" = remove "heroic";
    "remove.gaming.geforce-now" = hide;
    "remove.gaming.battlenet" = hide;

    # ---- Update ----------------------------------------------------------
    "update.omarchy" = { label = "Everything (flake inputs)"; action = term "omarchy-update inputs"; };
    "update.system" = { icon = g "f013"; label = "Apply Config"; action = term "omarchy-update system"; };
    "update.rollback" = { icon = "󰕌"; label = "Roll Back"; action = term "omarchy-update rollback"; };
    "update.clean" = { icon = "󰃢"; label = "Garbage Collect"; action = term "omarchy-update clean"; };
    "update.channel" = hide;
    "update.config" = hide;
    "update.themes" = hide;
    "update.firmware" = hide;
    "update.timezone" = hide;
    "update.time" = hide;
    "update.password.drive" = hide;
  };

  overrides = baseOverrides // unpackagedAgents;

  # The channels run different upstream versions, so an override for an
  # entry this version's menu doesn't have is skipped; entries this file adds
  # itself carry their own icon.
  applicable = lib.filterAttrs (id: o: upstream ? ${id} || o ? icon) overrides;
  merged = lib.mapAttrs (id: o: (upstream.${id} or { }) // o) applicable;
  missingIcon = builtins.filter
    (id: (merged.${id}.when or "") != "false" && (merged.${id}.icon or "") == "")
    (builtins.attrNames merged);
in
assert missingIcon == [ ] || throw
  "omarchy lib/menu.nix: menu entries without an icon: ${toString missingIcon}";
builtins.toJSON merged
