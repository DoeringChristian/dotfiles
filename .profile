# pixi env (replaces the old nix profile) for POSIX login shells
export PATH="$HOME/dotfiles/.pixi/envs/default/bin:$HOME/.pixi/bin:$HOME/.local/bin:$PATH"
# rustup is gone (pixi provides `rust`); source cargo env only if it exists
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
export EDITOR=nvim
