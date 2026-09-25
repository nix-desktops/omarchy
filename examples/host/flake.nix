{
  description = "A NixOS machine running the Omarchy desktop";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # The desktop. Pick a channel with the branch: stable, rc or edge.
    omarchy = {
      url = "github:nix-desktops/omarchy/stable";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
  };

  outputs = { nixpkgs, home-manager, omarchy, ... }: {
    nixosConfigurations.omarchy = nixpkgs.lib.nixosSystem {
      modules = [
        home-manager.nixosModules.home-manager
        omarchy.nixosModules.default
        ./hardware-configuration.nix
        ./configuration.nix
      ];
    };
  };
}
