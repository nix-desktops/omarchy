# Omarchy's CLI setup (PACKAGES.md group 3): its shell setup (upstream
# default/bash: envs, aliases, functions, history, completion, prompt) and
# its configs for the command-line programs and terminals, all defaults.
#
#   omarchy.shell            the shell that gets the setup: zsh (upstream's
#                            omarchy-zsh + the shared default/bash, see
#                            omarchy.zsh) or bash (upstream's rc as it is)
#   omarchy.configs.<name>   per-program opt-out
#
# Configs are upstream's own files (config/ and etc/ in the omarchy input).
# A host that enables Home Manager's programs.<name> manages that program's
# config itself, so Omarchy's steps aside; otherwise it's linked below
# `mkDefault`, so the host's own xdg.configFile (whose text is a mkDefault
# source) still wins. They take their colors from the current theme
# (~/.local/state/omarchy/current/theme), as upstream's do.
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
    btop = {
      "btop/btop.conf" = upstream "config/btop/btop.conf";
      # color_theme = "current"
      "btop/themes/current.theme" = "${cfg.currentTheme}/btop.theme";
    };
    lazygit = { "lazygit/config.yml" = upstream "config/lazygit/config.yml"; };
    fastfetch = { "fastfetch/config.jsonc" = upstream "etc/fastfetch/config.jsonc"; };
    alacritty = { "alacritty/alacritty.toml" = upstream "config/alacritty/alacritty.toml"; };
    ghostty = { "ghostty/config" = upstream "config/ghostty/config"; };
    kitty = { "kitty/kitty.conf" = upstream "config/kitty/kitty.conf"; };
  };

  configOption = name: description: {
    enable = mkOption {
      type = types.bool;
      default = true;
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
    (lib.mkIf (cfg.configs.shell.enable && cfg.shell == "zsh") {
      programs.zsh.enable = mkDefault true;
      # Before the host's own init (default order 1000), so its settings win.
      programs.zsh.initContent = lib.mkOrder 800 ''
        source ${zshSetup}
      '';
    })

    (lib.mkIf (cfg.configs.shell.enable && cfg.shell == "bash") {
      programs.bash.enable = mkDefault true;
      programs.bash.initExtra = lib.mkBefore ''
        source "$OMARCHY_PATH/default/bash/rc"
      '';
    })

    {
      xdg.configFile = lib.concatMapAttrs (name: files:
        lib.optionalAttrs (cfg.configs.${name}.enable && !(config.programs.${name}.enable or false))
          (lib.mapAttrs (_: source: { source = lib.mkOverride 1100 source; }) files))
        programs;
    }
  ]);
}
