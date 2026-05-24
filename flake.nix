{
  description = "Cross-platform dotfiles (Linux & macOS)";

  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    neovim-nightly-overlay = {
      url = "github:nix-community/neovim-nightly-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-utils.url = "github:numtide/flake-utils";

    sshr = {
      url = "github:DoeringChristian/sshr";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
  };

  outputs = {
    nixpkgs,
    neovim-nightly-overlay,
    flake-utils,
    sshr,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      isLinux = builtins.match ".*linux.*" system != null;
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [neovim-nightly-overlay.overlays.default];
      };
    in {
      packages.default = pkgs.buildEnv {
        name = "dotfiles";
        paths = with pkgs;
          [
            # Development tools
            vim
            neovim
            tree
            ripgrep
            fd
            curl
            wget
            stow
            pixi
            uv
            rustup
            nodejs
            python3
            tree-sitter

            # Utilities
            unzip
            zip
            gzip
            which
            file
            less

            # Secrets
            age
            passage

            # System monitoring
            btop
            ncdu
            duf

            # Shell & CLI tools
            starship
            direnv
            eza
            bat
            claude-code
            claude-agent-acp
            gemini-cli
            atuin
            zoxide
            zellij
            fish
            fzf
            gh
            git
            git-lfs
            dust
            lazygit
            mosh
            nmap
            sshr.packages.${system}.default

            # Type Setting
            typst

            # Fonts
            nerd-fonts.fira-code
          ]
          ++ (
            if isLinux
            then [
              # Linux-only: clipboard
              wl-clipboard
              xsel

              # Linux-only: containers & GPU monitoring
              distrobox # run `distrobox create --nvidia --name ubuntu --image ubuntu:latest`
              nvtopPackages.full

              # Linux-only: network tools
              net-tools
              inetutils
              traceroute
              vpn-slice
              openconnect

              # Linux-only: LLMs
              ollama
            ]
            else []
          );
      };
    });
}
