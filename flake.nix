{
  description = "Omarchy on NixOS: Omarchy's Quickshell shell, commands, themes, keybinds and Hyprland config, taken from upstream and adapted declaratively";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # Omarchy's shell needs Quickshell 0.3.1; 26.05 ships 0.3.0.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Upstream Omarchy. Which ref this follows depends on the branch of this
    # repo (the release channel): stable → newest v4.* release tag,
    # rc → newest pre-release tag, edge/main → the `quattro` branch. CI
    # (.github/workflows/update-omarchy.yml) keeps it current.
    omarchy = {
      url = "github:basecamp/omarchy/v4.0.4";
      flake = false;
    };

    # Omarchy's zsh setup (options, key bindings, completion, fzf widgets);
    # the shared shell config comes from the omarchy input's default/bash.
    omarchy-zsh = {
      url = "github:omacom/omarchy-zsh";
      flake = false;
    };

    # Omarchy's own tools (pkgs/tools), each from its upstream repo at the
    # version Omarchy ships (omacom/omarchy-pkgs' PKGBUILDs).
    omasnap = { url = "github:omacom/omasnap/v1.21.0"; flake = false; };
    ttfx = { url = "github:omacom/ttfx/v0.3.3"; flake = false; };
    owe = { url = "github:omacom/owe/v0.2.6"; flake = false; };
    elsewhen = { url = "github:omacom/elsewhen/v1.0.0"; flake = false; };
    omacut = { url = "github:omacom/omacut/v0.4.0"; flake = false; };
    omacalc = { url = "github:omacom/omacalc/v0.2.2"; flake = false; };
    omawrite = { url = "github:omacom/omawrite/v0.5.0"; flake = false; };
    aether = { url = "github:omacom/aether/v4.30.0"; flake = false; };
    herdr = { url = "github:herdrdev/herdr/v0.9.1"; flake = false; };
    tobi-try = { url = "github:tobi/try/d1bc484cc31a34db3d287550f4800e9a6e56bacd"; flake = false; };
    # Omarchy's packaging: omarchy-nvim's config, omacalc's launcher.
    omarchy-pkgs = { url = "github:omacom/omarchy-pkgs"; flake = false; };
    lazyvim-starter = { url = "github:LazyVim/starter"; flake = false; };

    # Per-project dev environments for Install > Development.
    dev-templates = {
      url = "github:nix-templates/dev";
      flake = false;
    };

    # Only for the example host and the VM test.
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, ... }@inputs:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      # The desktop, as Home Manager and NixOS modules. They carry this
      # flake's inputs themselves, so hosts need no extra specialArgs.
      # Keyed, so a host that imports the Home Manager module itself and
      # also lists the user in the NixOS module's `omarchy.users` gets it once.
      homeManagerModules.default = {
        key = "nix-desktops/omarchy/home";
        imports = [ (import ./modules/home { inherit inputs; }) ];
      };
      nixosModules.default = {
        key = "nix-desktops/omarchy/nixos";
        imports = [ (import ./modules/nixos { inherit inputs; inherit (self) homeManagerModules; }) ];
      };

      # Theme registry, for host config that needs the active palette at
      # evaluation time (e.g. a Stylix base16 scheme):
      #   omarchy.lib.theme { stateDir = ./omarchy; }
      lib.theme = { stateDir }: import ./lib/theme.nix { inherit (inputs) omarchy; inherit stateDir; };

      # Everything the desktop can install, as data, grouped as PACKAGES.md
      # decides: the defaults (CLI setup, TUI launchers), Omarchy's ecosystem
      # (apps, web apps, development) and what's only picked (agents, tools),
      # with the ids the options take. For installers:
      #   nix eval --json github:nix-desktops/omarchy#lib.catalog
      # Omarchy's keybinds are `packages.<system>.keybinds`.
      lib.catalog = import ./lib/catalog.nix;

      # The dev environments behind Install > Development, also usable
      # directly: `nix flake new -t github:nix-desktops/omarchy#rust myproject`.
      # Every nix-templates/dev template plus the framework layers in
      # ./templates (laravel, symfony, phoenix).
      #
      # `host` is a whole NixOS machine running this desktop:
      #   nix flake new -t github:nix-desktops/omarchy#host ~/nixos
      templates = builtins.mapAttrs (_: t: removeAttrs t [ "base" ])
        (import ./lib/dev-templates.nix {
          inherit (nixpkgs) lib;
          src = inputs.dev-templates;
          local = ./templates;
        }).all // {
          host = {
            path = ./examples/host;
            description = "A NixOS machine running the Omarchy desktop";
            welcomeText = builtins.readFile ./examples/host/WELCOME.md;
          };
        };

      packages = forAllSystems (pkgs: {
        default = self.packages.${pkgs.stdenv.hostPlatform.system}.omarchy;
        # Upstream Omarchy as-is (shebangs patched). The Home Manager module
        # builds its own copy with the NixOS command layer installed on top.
        omarchy = pkgs.callPackage ./pkgs/omarchy.nix {
          src = inputs.omarchy;
          plugins = [ self.packages.${pkgs.stdenv.hostPlatform.system}.elsewhen ];
        };
      } // (import ./pkgs/tools { inherit pkgs inputs; }) // {
        # Omarchy's default keybinds as data (keybinds.json).
        keybinds = pkgs.callPackage ./pkgs/keybinds { src = inputs.omarchy; };
      });

      checks = forAllSystems (pkgs: import ./tests { inherit inputs pkgs self; });

      formatter = forAllSystems (pkgs: pkgs.nixfmt);
    };
}
