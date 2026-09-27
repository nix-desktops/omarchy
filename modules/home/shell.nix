# Omarchy's CLI setup (PACKAGES.md group 3): its shell setup (upstream
# default/bash: envs, aliases, functions, history, completion, prompt) and
# its configs for the command-line programs and terminals, all defaults.
#
#   omarchy.shell            the shell that gets the setup: zsh (upstream's
#                            omarchy-zsh + the shared default/bash, see
#                            omarchy.zsh) or bash (upstream's ~/.bashrc)
#   omarchy.configs.<name>   per-program opt-out
#
# Configs are upstream's own files (config/ and etc/ in the omarchy input),
# seeded once as the user's files (seed.nix), as upstream copies them. A host
# that enables Home Manager's programs.<name>, or links the file itself,
# manages that config, so Omarchy's steps aside. They take their colors from
# the current theme (~/.local/state/omarchy/current/theme), as upstream's do.
{ inputs }:
{ config, lib, pkgs, ... }:
let
  cfg = config.omarchy;
  inherit (lib) mkOption types mkDefault;

  # Upstream's bash setup, with the one line zsh reads differently: `read -p`
  # (prompt in bash, coprocess in zsh/ksh) becomes zsh's `read "var?prompt"`.
  bashSetup = pkgs.runCommand "omarchy-shell-setup" { } ''
    cp -r ${inputs.omarchy}/default/bash $out
    chmod -R u+w $out
    sed -i -E 's/read -rp "([^"]*)" ([A-Za-z_]+)/read -r "\2?\1"/' $out/fns/*
  '';
  # omarchy-zsh's own files, with its Arch plugin path pointed at nixpkgs.
  zshFiles = pkgs.runCommand "omarchy-zsh" { } ''
    cp -r ${inputs.omarchy-zsh} $out
    chmod -R u+w $out
    substituteInPlace $out/shell/zoptions --replace-fail \
      /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh \
      ${pkgs.zsh-syntax-highlighting}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
  '';
  zshSetup = pkgs.replaceVars ./omarchy.zsh { bash = bashSetup; zsh = zshFiles; };

  upstream = path: inputs.omarchy + "/${path}";

  # Program configs: name → (xdg.configFile target → upstream source).
  programs = {
    foot = { "foot/foot.ini" = upstream "config/foot/foot.ini"; };
    starship = { "starship.toml" = upstream "config/starship.toml"; };
    tmux = { "tmux/tmux.conf" = upstream "config/tmux/tmux.conf"; };
    # color_theme = "current": btop/themes/current.theme, below.
    btop = { "btop/btop.conf" = upstream "config/btop/btop.conf"; };
    lazygit = { "lazygit/config.yml" = upstream "config/lazygit/config.yml"; };
    # The OS line says omarchy.branding.name.
    fastfetch = { "fastfetch/config.jsonc" = if cfg.branding.name == "Omarchy"
      then upstream "etc/fastfetch/config.jsonc"
      else pkgs.runCommand "fastfetch-config.jsonc" { } ''
        substitute ${upstream "etc/fastfetch/config.jsonc"} $out \
          --replace-fail 'echo \"Omarchy $version\"' ${lib.escapeShellArg "echo \\\"${cfg.branding.name} $version\\\""}
      ''; };
    alacritty = { "alacritty/alacritty.toml" = upstream "config/alacritty/alacritty.toml"; };
    ghostty = { "ghostty/config" = upstream "config/ghostty/config"; };
    kitty = { "kitty/kitty.conf" = upstream "config/kitty/kitty.conf"; };
  };

  # A default app's config follows the app (omarchy.defaultApps.<name>).
  configOption = name: description: {
    enable = mkOption {
      type = types.bool;
      default = cfg.defaultApps.${name}.enable or true;
      defaultText = lib.literalMD "`true` (for a default app: whether it's installed)";
      inherit description;
    };
  };
in
{
  options.omarchy = {
    shell = mkOption {
      type = types.enum [ "zsh" "bash" ];
      default = "zsh";
      description = ''
        The shell that gets Omarchy's setup (aliases, functions, history,
        completion, the starship prompt, zoxide, fzf, mise). Omarchy itself
        uses bash; zsh gets a port of the same setup. The NixOS module makes
        it the users' login shell.
      '';
    };

    configs = {
      shell = configOption "shell" "Omarchy's shell setup for `omarchy.shell`.";
      git = configOption "git" ''
        Omarchy's git defaults (aliases, rebase on pull, histogram diffs,
        rerere, …). They're system-wide (/etc/gitconfig, the NixOS module's
        `omarchy.configs.git.enable`), below every user's own git config.
      '';
    } // lib.mapAttrs (name: _: configOption name "Omarchy's ${name} config.") programs;
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    # zsh. Upstream's ~/.bashrc is a user file that sources Omarchy's rc; here
    # ~/.zshrc is the same: seeded once (seed.nix), sourcing the managed
    # setup, then the user's own lines. A host that manages ~/.zshrc through
    # Home Manager's programs.zsh gets the setup in there instead.
    (lib.mkIf (cfg.configs.shell.enable && cfg.shell == "zsh" && config.programs.zsh.enable) {
      # Before the host's own init (default order 1000), so its settings win.
      programs.zsh.initContent = lib.mkOrder 800 ''
        source ${zshSetup}
      '';
    })
    (lib.mkIf (cfg.configs.shell.enable && cfg.shell == "zsh" && !config.programs.zsh.enable) {
      # Session variables for every zsh (login, scripts, ssh commands), as
      # Home Manager's own ~/.zshenv does; also the user's file.
      home.file.".local/share/omarchy-nixos/zshenv".text = ''
        # Home Manager's session variables, managed by nix-desktops/omarchy.
        [[ -r ${config.home.profileDirectory}/etc/profile.d/hm-session-vars.sh ]] \
          && source ${config.home.profileDirectory}/etc/profile.d/hm-session-vars.sh
      '';
      omarchy.seededFiles.".zshenv".adopt = false;
      omarchy.seededFiles.".zshenv".source = pkgs.writeText "zshenv" ''
        # Session variables (managed); add your own below.
        source ~/.local/share/omarchy-nixos/zshenv
      '';
      home.file.".local/share/omarchy-nixos/zshrc".text = ''
        # Omarchy's shell setup for zsh, managed by nix-desktops/omarchy
        # (rewritten on every rebuild). Your own lines go in ~/.zshrc.
        [[ -r ${config.home.profileDirectory}/etc/profile.d/hm-session-vars.sh ]] \
          && source ${config.home.profileDirectory}/etc/profile.d/hm-session-vars.sh
        source ${zshSetup}
      '';
      omarchy.seededFiles.".zshrc".adopt = false;
      omarchy.seededFiles.".zshrc".source = pkgs.writeText "zshrc" ''
        # All the default Omarchy aliases and functions
        # (don't mess with these directly, just overwrite them here!)
        source ~/.local/share/omarchy-nixos/zshrc

        # Add your own exports, aliases, and functions here.
        #
        # Make an alias for invoking commands you use constantly
        # alias p='python'
      '';
    })

    # bash: upstream's own ~/.bashrc (default/bashrc), sourcing its rc from
    # OMARCHY_PATH, and a ~/.bash_profile that reads it in login shells (as
    # Arch's skeleton does). A host that manages them through Home Manager's
    # programs.bash gets the rc sourced there instead.
    (lib.mkIf (cfg.configs.shell.enable && cfg.shell == "bash" && config.programs.bash.enable) {
      programs.bash.initExtra = lib.mkBefore ''
        source "$OMARCHY_PATH/default/bash/rc"
      '';
    })
    (lib.mkIf (cfg.configs.shell.enable && cfg.shell == "bash" && !config.programs.bash.enable) {
      omarchy.seededFiles.".bashrc".adopt = false;
      omarchy.seededFiles.".bash_profile".adopt = false;
      omarchy.seededFiles.".bashrc".source = pkgs.runCommand "bashrc" { } ''
        {
          echo '# Session variables (Home Manager)'
          echo '[[ -r ${config.home.profileDirectory}/etc/profile.d/hm-session-vars.sh ]] && source ${config.home.profileDirectory}/etc/profile.d/hm-session-vars.sh'
          # Upstream's bootstrap points OMARCHY_PATH at /usr/share/omarchy;
          # the session sets it here.
          grep -v 'env-bootstrap' ${upstream "default/bashrc"}
        } >$out
      '';
      omarchy.seededFiles.".bash_profile".source = pkgs.writeText "bash_profile" ''
        [[ -f ~/.bashrc ]] && . ~/.bashrc
      '';
    })

    # Program configs: the user's files, seeded once from upstream (seed.nix;
    # they follow the theme through their includes of
    # ~/.local/state/omarchy/current/theme). Steps aside when the host
    # enables Home Manager's programs.<name>.
    {
      omarchy.seededFiles = lib.concatMapAttrs (name: files:
        lib.optionalAttrs (cfg.configs.${name}.enable && !(config.programs.${name}.enable or false))
          (lib.mapAttrs' (target: source: lib.nameValuePair ".config/${target}" { inherit source; }) files))
        programs;
    }
    # btop's theme is the current Omarchy theme's (as upstream links it).
    (lib.mkIf (cfg.configs.btop.enable && !(config.programs.btop.enable or false)) {
      xdg.configFile."btop/themes/current.theme".source =
        config.lib.file.mkOutOfStoreSymlink "${config.xdg.stateHome}/omarchy/current/theme/btop.theme";
    })
  ]);
}
