function fish_user_key_bindings
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

    # Mapping for jk to escape
    bind --mode insert --sets-mode default jk cancel repaint-mode
    # Mapping for jj to j
    bind -M insert jj 'commandline -i j'

    #Mapping for clipboard in vim mode
    bind yy fish_clipboard_copy
    bind Y fish_clipboard_copy
    bind p fish_clipboard_paste

    # Accept auto suggestions with `l`
    bind -M default l accept-autosuggestion
end
