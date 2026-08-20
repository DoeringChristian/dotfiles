# POSIX login-shell profile. The toolset is Homebrew; put its prefix on PATH.
for b in /opt/homebrew/bin /usr/local/bin /home/linuxbrew/.linuxbrew/bin; do
    [ -x "$b/brew" ] && eval "$("$b/brew" shellenv)" && break
done
export PATH="$HOME/.local/bin:$PATH:$HOME/.pixi/bin"
export EDITOR=nvim
