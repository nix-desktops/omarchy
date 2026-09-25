{
  description = "Elixir + Phoenix development environment: the nix-templates/dev Elixir stack plus inotify-tools for live reload";

  # Layered on nix-templates/dev's elixir environment: its devShell (toolchain,
  # LSP, linters, formatters, scanners, lint/fmt/scan) comes in through
  # inputsFrom, and this flake only adds the framework tooling on top.
  inputs = {
    base.url = "github:nix-templates/dev?dir=elixir";
    nixpkgs.follows = "base/nixpkgs";
  };

  outputs = { base, nixpkgs, ... }:
    let
      forEachSupportedSystem = f: nixpkgs.lib.genAttrs
        (builtins.attrNames base.devShells)
        (system: f { inherit system; pkgs = nixpkgs.legacyPackages.${system}; });
    in {
      devShells = forEachSupportedSystem ({ pkgs, system }: {
        default = pkgs.mkShellNoCC {
          inputsFrom = [ base.devShells.${system}.default ];
          packages = with pkgs; [ inotify-tools ];
          shellHook = ''
            echo "Scaffold with: mix archive.install hex phx_new && mix phx.new ."
          '';
        };
      });
    };
}
