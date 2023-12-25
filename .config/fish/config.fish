if status is-interactive
    # Commands to run in interactive sessions can go here
end

function l
    ls -l -g
end

if type -q eza
  alias l "eza -l -g --icons"
  alias ll "l -a"
  alias la "ll"
end

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

# Mapping for jk to escape
bind --mode insert --sets-mode default jk repaint
# Mapping for jj to j
bind -M insert jj 'commandline -i j'

# Ocaml
source /home/doeringc/.opam/opam-init/init.fish > /dev/null 2> /dev/null; or true

# Starship
starship init fish | source
