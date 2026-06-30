# POSIX login-shell profile — mise edition (replaces the ~/.pixi/bin one).
# mise's shims expose the managed tools; we put them on PATH directly (like
# pixi's ~/.pixi/bin) and deliberately do NOT run `mise activate` — its
# per-prompt hook can pile up processes on a slow version resolution.
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"
export EDITOR=nvim
