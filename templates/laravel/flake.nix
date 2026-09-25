{
  description = "PHP + Laravel development environment: the nix-templates/dev PHP stack plus Node.js and the Laravel installer";

  # Layered on nix-templates/dev's php environment: its devShell (toolchain,
  # LSP, linters, formatters, scanners, lint/fmt/scan) comes in through
  # inputsFrom, and this flake only adds the framework tooling on top.
  inputs = {
    base.url = "github:nix-templates/dev?dir=php";
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
          packages = with pkgs; [ nodejs laravel ];
          shellHook = ''
            echo "Scaffold with: laravel new ."
          '';
        };
      });
    };
}
