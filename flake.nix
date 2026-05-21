{
  description = "Cross-platform dotfiles (Linux & macOS)";

  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # NixGL - using PR #187 with nvidia version detection fix
    nixgl = {
      url = "github:nix-community/nixGL/pull/187/head";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    neovim-nightly-overlay = {
      url = "github:nix-community/neovim-nightly-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    nixpkgs,
    nixgl,
    neovim-nightly-overlay,
    flake-utils,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      isLinux = builtins.match ".*linux.*" system != null;
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays =
          [neovim-nightly-overlay.overlays.default]
          ++ (
            if isLinux
            then [nixgl.overlay]
            else []
          );
      };
      # On Linux, wrap GPU apps with nixGLIntel; on macOS, just pass through
      nixGLWrap =
        if isLinux
        then
          pkg:
            pkgs.writeShellScriptBin pkg.pname ''
              exec ${pkgs.nixgl.nixGLIntel}/bin/nixGLIntel ${pkg}/bin/${pkg.pname} "$@"
            ''
        else pkg: pkg;
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
            tectonic
            dust
            lazygit
            devenv
            nmap

            # Type Setting
            typst

            # Fonts
            nerd-fonts.fira-code

            # Graphical applications (nixGLWrap is identity on macOS)
            (nixGLWrap kitty)
            zathura
            (nixGLWrap tev)
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
