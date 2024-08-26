if status is-interactive
    # Commands to run in interactive sessions can go here
end

#----------- config -----------

fish_vi_key_bindings

# Emulates vim's cursor shape behavior
# Set the normal and visual mode cursors to a block
set fish_cursor_default block
# Set the insert mode cursor to a line
set fish_cursor_insert line
# Set the replace mode cursor to an underscore
set fish_cursor_replace_one underscore
# The following variable can be used to configure cursor shape in
# visual mode, but due to fish_cursor_default, is redundant here
set fish_cursor_visual block

# Set timeout
set -g fish_sequence_key_delay_ms 200

#----------- sourcing external stuff -----------

# Ocaml
# source /home/doeringc/.opam/opam-init/init.fish > /dev/null 2> /dev/null; or true

# Starship
starship init fish | source

# Autin
if type -q atuin
    atuin init fish | source
    bind \cr _atuin_search
    bind -M insert \cr _atuin_search
end

# nix
if type -q nix
    source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.fish
end

# direnv
if type -q direnv
    direnv hook fish | source
    set -g direnv_fish_mode eval_on_arrow
end
