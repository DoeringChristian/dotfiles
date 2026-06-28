# POSIX login-shell profile — mise edition (replaces the ~/.pixi/bin one).
# mise is installed to ~/.local/bin; its shims expose the managed tools.
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"
# Activate mise if available (manages PATH + tool versions per directory).
command -v mise >/dev/null 2>&1 && eval "$(mise activate bash)"
export EDITOR=nvim
