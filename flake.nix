{
  description = "Home Manager configuration for Ubuntu";

  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # NixGL - using PR #187 with nvidia version detection fix
    nixgl = {
      url = "github:nix-community/nixGL/pull/187/head";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    claudepod = {
      url = "github:doeringchristian/claudepod";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    nixpkgs,
    nixgl,
    claudepod,
    flake-utils,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [nixgl.overlay];
      };
      nixGLWrap = pkg:
        pkgs.writeShellScriptBin pkg.pname ''
          exec ${pkgs.nixgl.nixGLIntel}/bin/nixGLIntel ${pkg}/bin/${pkg.pname} "$@"
        '';
    in {
      packages.default = pkgs.buildEnv {
        name = "dotfiles";
        paths = with pkgs; [
          # Development tools
          vim
          neovim
          tree
          ripgrep
          fd
          curl
          wget
          stow
          ripgrep
          pixi

          # Utilities
          unzip
          zip
          gzip
          which
          file
          less
          wl-clipboard
          xsel

          # System monitoring
          btop
          ncdu
          duf

          # Utilities
          starship
          direnv
          eza
          bat
          btop
          claude-code
          claude-code-acp
          gemini-cli
          atuin
          zoxide
          fish
          fzf
          gh
          git
          git-lfs
          (nixGLWrap kitty)
          zathura
          tectonic
          distrobox # run `distrobox create --nvidia --name ubuntu --image ubuntu:latest` to create ubuntu nvidia container
          claudepod.packages.${system}.default

          (nixGLWrap tev)

          # Network tools
          net-tools
          inetutils
          nmap
          traceroute

          # Fonts
          nerd-fonts.fira-code

          # Inkscape with TexText extension
          (pkgs.inkscape-with-extensions.override {
            inkscapeExtensions = [
              pkgs.inkscape-extensions.textext
            ];
          })

          (nixGLWrap darktable)
        ];
      };
    });
}
