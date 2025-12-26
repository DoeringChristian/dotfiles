{
  description = "Home Manager configuration for Ubuntu";

  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # Home Manager
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # NixGL - using PR #187 with nvidia version detection fix
    nixgl = {
      url = "github:nix-community/nixGL/pull/187/head";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    catppuccin.url = "github:catppuccin/nix";

    claudepod = {
      url = "github:doeringchristian/claudepod";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    nixpkgs,
    home-manager,
    nixgl,
    catppuccin,
    claudepod,
    ...
  }: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
      overlays = [nixgl.overlay];
    };
  in {
    homeConfigurations."doeringc" = home-manager.lib.homeManagerConfiguration {
      inherit pkgs;

      # Specify your home configuration modules here
      modules = [
        ./home.nix
        catppuccin.homeModules.catppuccin
      ];

      # Pass nixGL and claudepod to home.nix
      extraSpecialArgs = {
        nixgl = nixgl;
        claudepod = claudepod;
      };
    };
  };
}
