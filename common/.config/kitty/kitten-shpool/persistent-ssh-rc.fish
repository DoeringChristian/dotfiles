# Deployed to remote via kitten ssh's copy directive.
# Placed in ~/.config/fish/conf.d/00-persistent-ssh.fish on the remote.

if set -q PERSISTENT_SSH_SESSION; and not set -q SHPOOL_SESSION_NAME
    # First fish (started by kitten ssh): exec into shpool
    set -l shpool_bin "$HOME/.cargo/bin/shpool"
    if test -x "$shpool_bin"
        set -l session "$PERSISTENT_SSH_SESSION"
        set -l shell_cmd (command -v fish || echo /bin/bash)
        set -e PERSISTENT_SSH_SESSION
        set -e PERSISTENT_SSH_SHELL
        exec $shpool_bin attach -c "$shell_cmd" "$session"
    end
else if set -q SHPOOL_SESSION_NAME; and not set -q SSH_TTY
    # Second fish (inside shpool): shpool strips PATH, so restore it from
    # the system profile before anything else runs.
    for p in /run/current-system/sw/bin /run/wrappers/bin /etc/profiles/per-user/$USER/bin $HOME/.nix-profile/bin $HOME/.cargo/bin /usr/local/bin /usr/bin /bin
        if test -d $p; and not contains $p $PATH
            set -gx PATH $p $PATH
        end
    end
    # Fake SSH vars so starship shows hostname
    if command -q tty
        set -gx SSH_TTY (tty)
    end
    set -gx SSH_CONNECTION "shpool"
end
