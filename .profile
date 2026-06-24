# globally-installed pixi tools (pixi global) for POSIX login shells
export PATH="$HOME/.pixi/bin:$HOME/.local/bin:$PATH"
# rustup is gone (pixi provides `rust`); source cargo env only if it exists
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
export EDITOR=nvim
