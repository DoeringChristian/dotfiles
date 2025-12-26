# We use homemanager only for installing applications. Dotfiles are managed by gnu stow
{
  config,
  pkgs,
  lib,
  nixgl,
  claudepod,
  ...
}: {
  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = "doeringc";
  home.homeDirectory = "/home/doeringc";

  # allow unfree packages
  nixpkgs = {
    config = {
      allowUnfree = true;
      allowUnfreePredicate = _: true;
    };
  };

  nixGL.packages = nixgl.packages;
  nixGL.defaultWrapper = "mesa";
  nixGL.offloadWrapper = "nvidiaPrime";
  nixGL.installScripts = ["mesa" "nvidia" "nvidiaPrime"];

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  home.stateVersion = "25.05"; # Please read the comment before changing.

  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = with pkgs; [
    # Development tools
    vim
    neovim
    tree
    ripgrep
    fd
    curl
    wget
    stow

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
    atuin
    zoxide
    fish
    fzf
    gh
    git
    kitty
    zathura
    claudepod.packages.${pkgs.system}.default

    (config.lib.nixGL.wrap tev)

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

    (config.lib.nixGL.wrap darktable)
  ];

  # Ubuntu-specific: fontconfig for better font rendering
  fonts.fontconfig.enable = true;
}
